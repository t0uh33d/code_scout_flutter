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

  // Initialize and open the database
  Future<Database> get database async {
    if (_database != null) return _database!;

    // Initialize the database
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    // Get the database path
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'code_scout.db');

    // Open the database
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // Create logs table
        await db.execute('''
        CREATE TABLE logs (
          id TEXT PRIMARY KEY,
          session_id TEXT NOT NULL,
          level TEXT NOT NULL,
          message TEXT,
          error TEXT,
          stack_trace TEXT,       -- JSON array of stack call details
          metadata TEXT,          -- JSON-encoded Map
          tags TEXT,              -- JSON-encoded List
          timestamp TEXT,         -- ISO-8601 string
          is_network_call INTEGER NOT NULL DEFAULT 0,
          request_id TEXT,
          call_phase TEXT         -- Enum as string
        );
      ''');
      },
    );
  }

  Future<void> saveLogEntry(LogEntry logEntry) async {
    _database ??= await database;

    await _database?.insert('logs', logEntry.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>?> getLogEntries({int limit = 100}) async {
    final List<Map<String, dynamic>>? maps = await _database?.query(
      'logs',
      orderBy: 'timestamp ASC',
      limit: limit,
    );

    return maps;
  }

  Future<void> deleteLogEntries(List<String> ids) async {
    if (ids.isEmpty) return;

    final placeholders = List.filled(ids.length, '?').join(', ');
    await _database?.delete(
      'logs',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }
}
