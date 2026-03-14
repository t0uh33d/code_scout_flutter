import 'dart:async';
import 'dart:convert';

import 'package:code_scout/code_scout.dart';
import 'package:sqflite/sqflite.dart';

import 'package:path/path.dart';

class LogPersistenceService {
  static final LogPersistenceService i = LogPersistenceService._internal();

  LogPersistenceService._internal();

  factory LogPersistenceService() {
    return i;
  }

  Database? _database;
  Completer<Database>? _initCompleter;

  Future<Database> get database async {
    if (_database != null) return _database!;

    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<Database>();
    try {
      _database = await _initDatabase();
      _initCompleter!.complete(_database!);
    } catch (e, st) {
      _initCompleter!.completeError(e, st);
      _initCompleter = null;
      rethrow;
    }
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'code_scout.db');

    return await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA journal_mode=WAL');
      },
      onCreate: (db, version) async {
        await db.execute('''
        CREATE TABLE logs (
          id TEXT PRIMARY KEY,
          session_id TEXT NOT NULL,
          level TEXT NOT NULL,
          message TEXT,
          error TEXT,
          stack_trace TEXT,
          metadata TEXT,
          tags TEXT,
          timestamp TEXT,
          is_network_call INTEGER NOT NULL DEFAULT 0,
          request_id TEXT,
          call_phase TEXT,
          sync_status INTEGER NOT NULL DEFAULT 0
        );
        ''');
        await db.execute(
            'CREATE INDEX idx_logs_sync_status ON logs(sync_status, timestamp);');
      },
    );
  }

  Future<void> saveLogEntry(LogEntry logEntry) async {
    final db = await database;
    await db.insert('logs', logEntry.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getLogEntries({int limit = 100}) async {
    final db = await database;

    final List<Map<String, dynamic>> maps = await db.query(
      'logs',
      where: 'sync_status = ?',
      whereArgs: [0],
      orderBy: 'timestamp ASC',
      limit: limit,
    );

    return maps.map(_cleanDecodedLogEntry).toList();
  }

  Map<String, dynamic> _cleanDecodedLogEntry(Map<String, dynamic> raw) {
    return {
      ...raw,
      'tags': _safeJsonDecode(raw['tags'], fallback: []),
      'metadata': _safeJsonDecode(raw['metadata'], fallback: {}),
      'stack_trace': _safeJsonDecode(raw['stack_trace'], fallback: []),
    };
  }

  dynamic _safeJsonDecode(dynamic value, {required dynamic fallback}) {
    if (value is String) {
      try {
        return jsonDecode(value);
      } catch (_) {
        return fallback;
      }
    }
    return fallback;
  }

  /// Marks logs as pending sync (sync_status = 1) so they won't be
  /// picked up by another concurrent sync cycle.
  Future<void> markAsSyncing(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final id in ids) {
      batch.update('logs', {'sync_status': 1},
          where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  /// Resets logs back to unsync'd state (e.g. after a failed upload).
  Future<void> markAsUnsync(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final id in ids) {
      batch.update('logs', {'sync_status': 0},
          where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteLogEntries(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.delete(
      'logs',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
    _initCompleter = null;
  }
}
