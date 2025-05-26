import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DB {
  // Singleton instance
  static final DB _instance = DB._internal();

  // Database instance
  Database? _database;

  // Private constructor
  DB._internal();

  // Factory constructor to return the same instance
  factory DB() {
    return _instance;
  }

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
        // Create tables
        await db.execute(
          'CREATE TABLE Test (id INTEGER PRIMARY KEY, name TEXT, value INTEGER, num REAL)',
        );
      },
    );
  }

  // Insert data into the database
  Future<int> insert(String table, Map<String, dynamic> values) async {
    final db = await database;
    return await db.insert(table, values);
  }

  // Fetch data from the database
  Future<List<Map<String, dynamic>>> query(String table) async {
    final db = await database;
    return await db.query(table);
  }

  // Update data in the database
  Future<int> update(String table, Map<String, dynamic> values, String where,
      List<dynamic> whereArgs) async {
    final db = await database;
    return await db.update(table, values, where: where, whereArgs: whereArgs);
  }

  // Delete data from the database
  Future<int> delete(
      String table, String where, List<dynamic> whereArgs) async {
    final db = await database;
    return await db.delete(table, where: where, whereArgs: whereArgs);
  }

  // Close the database
  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
