import 'dart:async';
import 'dart:convert';

import 'package:code_scout/code_scout.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

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
    // The first caller gets its answer from the rethrow below, not from this
    // future, so on the failure path there is often nobody listening to it —
    // and an error delivered to a future nobody awaits is reported as an
    // unhandled async error. That turns "the database would not open", which
    // every caller here already handles, into a crash report from the library
    // that is supposed to stay quiet about its own problems. Anyone who did
    // arrive while this was in flight still sees the error.
    _initCompleter!.future.ignore();
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
      version: 2,
      onOpen: (db) async {
        await db.rawQuery('PRAGMA journal_mode=WAL');
      },
      onCreate: (db, version) async {
        await _createLogs(db);
        await _createSessions(db);
        await _createMeta(db);
      },
      // The package is published, so there are real databases on real phones
      // that only have the logs table. Adding the two new ones is all v2 is.
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createSessions(db);
          await _createMeta(db);
        }
      },
    );
  }

  Future<void> _createLogs(Database db) async {
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
  }

  Future<void> _createSessions(Database db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS sessions (
      id TEXT PRIMARY KEY,
      installation_id TEXT,
      user_id TEXT,
      device_model TEXT,
      os_name TEXT,
      os_version TEXT,
      app_version TEXT,
      build_number TEXT,
      metadata TEXT,
      started_at TEXT NOT NULL,
      last_seen_at TEXT NOT NULL
    );
    ''');
  }

  Future<void> _createMeta(Database db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS meta (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );
    ''');
  }

  /// The installation id: written once, then the same value for the life of
  /// the install. It lives in the SDK's own database, so uninstalling the app
  /// takes it with them — which is exactly what "installation" should mean.
  Future<String> installationId() async {
    final db = await database;

    final existing =
        await db.query('meta', where: 'key = ?', whereArgs: ['installation_id']);
    if (existing.isNotEmpty) {
      final value = existing.first['value'];
      if (value is String && value.isNotEmpty) return value;
    }

    final generated = const Uuid().v4();
    await db.insert(
      'meta',
      {'key': 'installation_id', 'value': generated},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return generated;
  }

  /// Stores the session, replacing what was there. The record changes as the
  /// launch goes on — setUser() lands, device info resolves, last-seen moves —
  /// and the local row is always the newest version of it.
  Future<void> saveSession(SessionRecord session) async {
    final db = await database;
    await db.insert('sessions', session.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// The sessions a batch of logs belongs to.
  ///
  /// A batch is not always the current launch: logs from a launch that was
  /// killed before it could sync are still in the table, and without their
  /// session record they would arrive on the dashboard as a row with no device
  /// and no user — the exact launch you would most want to look at.
  Future<List<SessionRecord>> getSessionsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await db.query(
      'sessions',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    return rows.map(SessionRecord.fromRow).toList();
  }

  /// Drops session records nothing refers to any more. [keepId] is the current
  /// launch, which has no logs left the moment a sync succeeds but is very much
  /// still running.
  Future<void> pruneSessions(String keepId) async {
    final db = await database;
    await db.rawDelete(
      'DELETE FROM sessions WHERE id != ? '
      'AND id NOT IN (SELECT DISTINCT session_id FROM logs)',
      [keepId],
    );
  }

  Future<void> saveLogEntry(LogEntry logEntry) async {
    final db = await database;
    await db.insert('logs', logEntry.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// How many logs are still on disk waiting to reach the server.
  ///
  /// Every row, not just the ones with sync_status = 0: a batch marked as
  /// in-flight has not arrived anywhere yet, and rows are only deleted once the
  /// server has taken them. This is the number the overlay should show, and it
  /// is not the size of the in-memory buffer the overlay draws its list from —
  /// that one is a display ring and never drains.
  Future<int> pendingCount() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM logs');
    return Sqflite.firstIntValue(rows) ?? 0;
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
