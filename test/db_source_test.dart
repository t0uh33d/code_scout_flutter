import 'package:code_scout/code_scout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY,
        email TEXT NOT NULL,
        auth_token TEXT,
        avatar BLOB
      )
    ''');
    await db.execute('CREATE TABLE "order" (ref TEXT, total_cents INTEGER)');
    await db.execute('CREATE VIEW v_open AS SELECT ref FROM "order"');
    await db.execute('CREATE TABLE kv (k TEXT PRIMARY KEY, v TEXT) WITHOUT ROWID');
    await db.insert('users', {'id': 1, 'email': 'ada@example.com', 'auth_token': 'secret'});
  });

  tearDown(() async => db.close());

  group('namespaces', () {
    test('tables and views are both listed, and told apart', () async {
      final found = await CodeScoutSqflite(db).namespaces();
      final byName = {for (final n in found) n.name: n.kind};

      expect(byName['users'], CodeScoutNamespaceKind.table);
      expect(byName['order'], CodeScoutNamespaceKind.table);
      expect(byName['v_open'], CodeScoutNamespaceKind.view);
    });

    test("SQLite's own bookkeeping tables are not offered", () async {
      // sqlite_sequence appears the moment an AUTOINCREMENT column exists.
      // Listing it would offer a developer a table they did not create and
      // cannot usefully read.
      await db.execute('CREATE TABLE auto (id INTEGER PRIMARY KEY AUTOINCREMENT)');
      await db.rawInsert('INSERT INTO auto (id) VALUES (NULL)');

      final names = (await CodeScoutSqflite(db).namespaces()).map((n) => n.name);
      expect(names, isNot(contains('sqlite_sequence')));
      expect(names, contains('auto'));
    });
  });

  group('describe', () {
    test('columns come back with their declared types and flags', () async {
      final schema = await CodeScoutSqflite(db).describe('users');
      final byName = {for (final c in schema.columns) c.name: c};

      expect(byName.keys, containsAll(['id', 'email', 'auth_token', 'avatar']));
      expect(byName['id']!.primaryKey, isTrue);
      expect(byName['id']!.declaredType, 'INTEGER');
      expect(byName['email']!.notNull, isTrue);
      expect(byName['email']!.primaryKey, isFalse);
      expect(byName['avatar']!.declaredType, 'BLOB');
    });

    test('an ordinary table is addressable by rowid', () async {
      final schema = await CodeScoutSqflite(db).describe('users');
      expect(schema.rowHandle, 'rowid');
      expect(schema.editable, isTrue);
      expect(schema.readOnlyBecause, isNull);
    });

    test('a view has no row to change, and says so', () async {
      // A cell that silently refuses to save reads as a bug. One that explains
      // itself reads as a boundary, which is why the reason is carried rather
      // than left for the write to discover.
      final schema = await CodeScoutSqflite(db).describe('v_open');
      expect(schema.editable, isFalse);
      expect(schema.rowHandle, isNull);
      expect(schema.readOnlyBecause, isNotNull);
      expect(schema.readOnlyBecause, contains('read but not changed'));
    });

    test('a WITHOUT ROWID table is read-only rather than wrongly addressed', () async {
      // It has a primary key that could serve, but supporting it properly means
      // handling composite keys, which changes the shape of every update. Until
      // somebody has one, refusing honestly beats guessing.
      final schema = await CodeScoutSqflite(db).describe('kv');
      expect(schema.editable, isFalse);
      expect(schema.readOnlyBecause, isNotNull);
    });

    test('a table named after a SQL keyword still works', () async {
      // `order` is a reserved word. Unquoted, PRAGMA table_info(order) is a
      // syntax error and the table would look like it does not exist.
      final schema = await CodeScoutSqflite(db).describe('order');
      expect(schema.columns.map((c) => c.name), containsAll(['ref', 'total_cents']));
    });

    test('an unknown namespace is an error, not an empty schema', () async {
      // Empty columns would render as a table with nothing in it, which reads
      // as "no data" rather than "no such table".
      expect(
        () => CodeScoutSqflite(db).describe('nope'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('redaction', () {
    test('a column the redaction config names is flagged', () async {
      await CodeScout.instance.init(
        configuration: CodeScoutConfiguration(
          redaction: const RedactionBehavior(bodyKeys: {'auth_token'}),
        ),
      );
      addTearDown(CodeScout.instance.dispose);

      final schema = await CodeScoutSqflite(db).describe('users');
      final byName = {for (final c in schema.columns) c.name: c};

      expect(byName['auth_token']!.redacted, isTrue);
      expect(byName['email']!.redacted, isFalse);
    });

    test('the match is case and separator insensitive, like body keys', () async {
      // authToken, auth_token and Auth-Token are one name everywhere else in
      // the SDK, and a column should not be the exception.
      await CodeScout.instance.init(
        configuration: CodeScoutConfiguration(
          redaction: const RedactionBehavior(bodyKeys: {'authToken'}),
        ),
      );
      addTearDown(CodeScout.instance.dispose);

      final schema = await CodeScoutSqflite(db).describe('users');
      final token = schema.columns.firstWhere((c) => c.name == 'auth_token');
      expect(token.redacted, isTrue);
    });

    test('nothing is flagged when nothing is configured', () async {
      // Stated rather than assumed: the configuration is a singleton that
      // outlives dispose(), so a test relying on whatever ran before it would
      // pass or fail depending on the order the file happened to run in.
      await CodeScout.instance.init(configuration: CodeScoutConfiguration());
      addTearDown(CodeScout.instance.dispose);

      final schema = await CodeScoutSqflite(db).describe('users');
      expect(schema.columns.every((c) => !c.redacted), isTrue);
    });
  });

  group('the registry', () {
    tearDown(DatabaseRegistry.i.clear);

    test('nothing is browsable until the app registers it', () {
      expect(DatabaseRegistry.i.isEmpty, isTrue);
      expect(DatabaseRegistry.i.sources, isEmpty);
    });

    test('registration order is kept, not alphabetical order', () {
      // The main database is nearly always registered first, so it should be
      // first in the dashboard's picker. Sorting would bury it.
      DatabaseRegistry.i.register('shop.db', CodeScoutSqflite(db));
      DatabaseRegistry.i.register('analytics.db', CodeScoutSqflite(db));
      DatabaseRegistry.i.register('cache.db', CodeScoutSqflite(db));

      expect(
        DatabaseRegistry.i.sources.map((s) => s.name),
        ['shop.db', 'analytics.db', 'cache.db'],
      );
    });

    test('a duplicate name throws rather than replacing', () {
      // Silently replacing means browsing one database while reading another's
      // name, and believing what you saw.
      DatabaseRegistry.i.register('shop.db', CodeScoutSqflite(db));
      expect(
        () => DatabaseRegistry.i.register('shop.db', CodeScoutSqflite(db)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an empty name throws', () {
      expect(
        () => DatabaseRegistry.i.register('', CodeScoutSqflite(db)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a source is read-only unless the app asked for more', () {
      DatabaseRegistry.i.register('read.db', CodeScoutSqflite(db));
      DatabaseRegistry.i.register('write.db', CodeScoutSqflite(db), writable: true);

      expect(DatabaseRegistry.i.find('read.db')!.writable, isFalse);
      expect(DatabaseRegistry.i.find('write.db')!.writable, isTrue);
    });

    test('an unregistered name is not found', () {
      expect(DatabaseRegistry.i.find('nope'), isNull);
    });

    test('registering through CodeScout reaches the registry', () {
      CodeScout.instance.registerDatabase('via-api.db', CodeScoutSqflite(db), writable: true);
      expect(DatabaseRegistry.i.find('via-api.db')!.writable, isTrue);
    });
  });
}
