import 'dart:convert';
import 'dart:typed_data';

import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/db/db_dispatcher.dart';
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
    await db.execute('CREATE TABLE flags (key TEXT NOT NULL, enabled INTEGER)');
    await db.insert('flags', {'key': 'checkout_v2', 'enabled': 0});
    await db.execute('CREATE VIEW v_flags AS SELECT key FROM flags');
  });

  tearDown(() async {
    DatabaseRegistry.i.clear();
    await db.close();
  });

  Future<int> rowid() async =>
      (await db.rawQuery('SELECT rowid FROM flags LIMIT 1')).first['rowid'] as int;

  group('sources', () {
    test('an app that registered nothing offers nothing', () async {
      final reply = await DatabaseDispatcher.handle('sources', {});
      expect(reply['ok'], isTrue);
      expect(reply['sources'], isEmpty);
    });

    test('registered databases come back with their writable flag', () async {
      DatabaseRegistry.i.register('shop.db', CodeScoutSqflite(db), writable: true);
      DatabaseRegistry.i.register('cache.db', CodeScoutSqflite(db));

      final reply = await DatabaseDispatcher.handle('sources', {});
      final sources = (reply['sources'] as List).cast<Map<String, dynamic>>();

      expect(sources.map((s) => s['name']), ['shop.db', 'cache.db']);
      expect(sources.first['writable'], isTrue);
      expect(sources.last['writable'], isFalse);
      expect(sources.first['kind'], 'sql');
    });
  });

  group('namespaces and schema', () {
    setUp(() => DatabaseRegistry.i.register('shop.db', CodeScoutSqflite(db), writable: true));

    test('namespaces lists tables and views', () async {
      final reply = await DatabaseDispatcher.handle('namespaces', {'db': 'shop.db'});
      final names = (reply['namespaces'] as List).map((n) => n['name']);
      expect(names, containsAll(['flags', 'v_flags']));
    });

    test('schema carries the columns and whether the source may be written', () async {
      final reply = await DatabaseDispatcher.handle(
          'schema', {'db': 'shop.db', 'namespace': 'flags'});

      expect(reply['ok'], isTrue);
      expect(reply['writable'], isTrue);
      final schema = reply['schema'] as Map<String, dynamic>;
      expect(schema['row_handle'], 'rowid');
      expect((schema['columns'] as List).map((c) => c['name']), ['key', 'enabled']);
    });

    test('a view says why it cannot be edited', () async {
      final reply = await DatabaseDispatcher.handle(
          'schema', {'db': 'shop.db', 'namespace': 'v_flags'});
      final schema = reply['schema'] as Map<String, dynamic>;
      expect(schema['row_handle'], isNull);
      expect(schema['read_only_because'], isNotNull);
    });
  });

  group('rows', () {
    setUp(() => DatabaseRegistry.i.register('shop.db', CodeScoutSqflite(db)));

    test('a page comes back with columns, rows and handles', () async {
      final reply = await DatabaseDispatcher.handle(
          'rows', {'db': 'shop.db', 'namespace': 'flags'});

      expect(reply['ok'], isTrue);
      final page = reply['page'] as Map<String, dynamic>;
      expect(page['rows'], hasLength(1));
      expect(page['handles'], hasLength(1));
      expect(page['has_more'], isFalse);
    });

    test('the whole reply survives a JSON round trip', () async {
      // It has to: this is handed straight to the socket, and a value that
      // cannot be encoded takes the frame with it. Blobs and over-long strings
      // are exactly the values that would.
      await db.execute('CREATE TABLE binary_stuff (payload BLOB, note TEXT)');
      await db.insert('binary_stuff', {
        'payload': Uint8List.fromList(List.filled(2048, 7)),
        'note': 'x' * 9000,
      });

      final reply = await DatabaseDispatcher.handle(
          'rows', {'db': 'shop.db', 'namespace': 'binary_stuff'});

      final encoded = jsonEncode(reply);
      expect(encoded, isNot(contains('Uint8List')));
      expect(jsonDecode(encoded), isA<Map>());
    });
  });

  group('update', () {
    test('a writable source accepts a change', () async {
      DatabaseRegistry.i.register('shop.db', CodeScoutSqflite(db), writable: true);

      final reply = await DatabaseDispatcher.handle('update', {
        'db': 'shop.db',
        'namespace': 'flags',
        'column': 'enabled',
        'handle': await rowid(),
        'value': '1',
        'was': 0,
      });

      expect(reply['ok'], isTrue);
      expect((await db.rawQuery('SELECT enabled FROM flags')).first['enabled'], 1);
    });

    test('a browse-only source is refused here too, not only at the registry', () async {
      // The op goes through the registry rather than straight to the source
      // precisely so this cannot be routed around.
      DatabaseRegistry.i.register('shop.db', CodeScoutSqflite(db));

      final reply = await DatabaseDispatcher.handle('update', {
        'db': 'shop.db',
        'namespace': 'flags',
        'column': 'enabled',
        'handle': await rowid(),
        'value': '1',
        'was': 0,
      });

      expect(reply['ok'], isFalse);
      expect(reply['message'], contains('browsing only'));
      expect((await db.rawQuery('SELECT enabled FROM flags')).first['enabled'], 0);
    });

    test('a conflict carries the current value back', () async {
      DatabaseRegistry.i.register('shop.db', CodeScoutSqflite(db), writable: true);
      await db.rawUpdate('UPDATE flags SET enabled = 9');

      final reply = await DatabaseDispatcher.handle('update', {
        'db': 'shop.db',
        'namespace': 'flags',
        'column': 'enabled',
        'handle': await rowid(),
        'value': '1',
        'was': 0,
      });

      expect(reply['code'], 'row_changed');
      expect(reply['current'], 9);
    });
  });

  group('nothing throws out of a dispatch', () {
    // Every one of these has to come back as an answer. A dashboard that gets
    // no reply waits out its full timeout and then cannot tell a broken query
    // from a phone that went to sleep.
    setUp(() => DatabaseRegistry.i.register('shop.db', CodeScoutSqflite(db), writable: true));

    test('an unknown op', () async {
      final reply = await DatabaseDispatcher.handle('drop_everything', {'db': 'shop.db'});
      expect(reply['ok'], isFalse);
      expect(reply['error'], contains('Unknown command'));
    });

    test('no database named', () async {
      final reply = await DatabaseDispatcher.handle('namespaces', {});
      expect(reply['ok'], isFalse);
    });

    test('a database that was never registered', () async {
      final reply = await DatabaseDispatcher.handle('namespaces', {'db': 'ghost.db'});
      expect(reply['ok'], isFalse);
      expect(reply['error'], contains('ghost.db'));
    });

    test('a table that does not exist', () async {
      final reply = await DatabaseDispatcher.handle(
          'schema', {'db': 'shop.db', 'namespace': 'nope'});
      expect(reply['ok'], isFalse);
    });

    test('a column that is not in the schema', () async {
      final reply = await DatabaseDispatcher.handle('rows', {
        'db': 'shop.db',
        'namespace': 'flags',
        'sort': 'key; DROP TABLE flags;--',
      });
      expect(reply['ok'], isFalse);
      // And the table is still there.
      expect((await db.rawQuery('SELECT count(*) c FROM flags')).first['c'], 1);
    });

    test('args of the wrong shape entirely', () async {
      final reply = await DatabaseDispatcher.handle('rows', {'db': 'shop.db'});
      expect(reply['ok'], isFalse);
    });
  });
}
