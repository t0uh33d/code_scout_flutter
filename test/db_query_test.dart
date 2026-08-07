import 'dart:convert';
import 'dart:typed_data';

import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/db/db_value.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late CodeScoutSqflite source;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE flags (
        key TEXT NOT NULL,
        enabled INTEGER,
        rollout REAL,
        note TEXT,
        payload BLOB
      )
    ''');
    await db.execute('CREATE VIEW v_flags AS SELECT key FROM flags');
    for (final row in [
      {'key': 'checkout_v2', 'enabled': 0, 'rollout': 12.5, 'note': 'staged'},
      {'key': 'checkout_one_tap', 'enabled': 1, 'rollout': 100.0, 'note': null},
      {'key': 'search_beta', 'enabled': 0, 'rollout': 0.0, 'note': 'off for now'},
    ]) {
      await db.insert('flags', row);
    }
    source = CodeScoutSqflite(db);
  });

  tearDown(() async {
    DatabaseRegistry.i.clear();
    await db.close();
  });

  Future<int> rowidOf(String key) async {
    final r = await db.rawQuery('SELECT rowid FROM flags WHERE key = ?', [key]);
    return r.first['rowid'] as int;
  }

  group('affinity', () {
    test("follows SQLite's own rules, in SQLite's own order", () {
      // Order is the whole point. POINT contains INT, so it is INTEGER, and
      // VARCHAR is only checked for CHAR after INT has been ruled out.
      expect(affinityOf('INTEGER'), SqliteAffinity.integer);
      expect(affinityOf('BIGINT'), SqliteAffinity.integer);
      expect(affinityOf('POINT'), SqliteAffinity.integer);
      expect(affinityOf('VARCHAR(255)'), SqliteAffinity.text);
      expect(affinityOf('CLOB'), SqliteAffinity.text);
      expect(affinityOf('BLOB'), SqliteAffinity.blob);
      expect(affinityOf(''), SqliteAffinity.blob);
      expect(affinityOf('REAL'), SqliteAffinity.real);
      expect(affinityOf('DOUBLE'), SqliteAffinity.real);
      expect(affinityOf('FLOAT'), SqliteAffinity.real);
      expect(affinityOf('DECIMAL(10,5)'), SqliteAffinity.numeric);
      expect(affinityOf('BOOLEAN'), SqliteAffinity.numeric);
    });
  });

  group('coercion', () {
    test('a number typed into an integer column is stored as a number', () {
      expect(coerceForColumn('42', 'INTEGER'), 42);
      expect(coerceForColumn('42', 'INTEGER'), isA<int>());
    });

    test('a real column takes a double', () {
      expect(coerceForColumn('12.5', 'REAL'), 12.5);
      expect(coerceForColumn('12.5', 'REAL'), isA<double>());
    });

    test('text stays text, even when it looks like a number', () {
      expect(coerceForColumn('42', 'TEXT'), '42');
      expect(coerceForColumn('42', 'TEXT'), isA<String>());
    });

    test('something unparseable is refused rather than stored as text', () {
      expect(() => coerceForColumn('banana', 'INTEGER'), throwsA(isA<CoercionError>()));
      expect(() => coerceForColumn('banana', 'REAL'), throwsA(isA<CoercionError>()));
    });

    test('NUMERIC takes the best fit, the way SQLite does', () {
      expect(coerceForColumn('7', 'DECIMAL'), 7);
      expect(coerceForColumn('7.5', 'DECIMAL'), 7.5);
      expect(coerceForColumn('later', 'DECIMAL'), 'later');
    });

    test('null means SQL NULL, not the string "null"', () {
      expect(coerceForColumn(null, 'TEXT'), isNull);
      expect(coerceForColumn(null, 'INTEGER'), isNull);
    });

    test('a column with no declared type takes what it is given', () {
      // SQLite rule 3 sends an untyped column to BLOB affinity, and BLOB
      // affinity means "store whatever you are given" rather than "this holds
      // bytes". `CREATE TABLE t (a, b)` is legal and common; refusing the
      // affinity made every such column permanently uneditable, with a message
      // about binary data that had nothing to do with it.
      expect(coerceForColumn('hello', ''), 'hello');
      expect(coerceForColumn('42', ''), '42');
      expect(coerceForColumn('anything', 'BLOB'), 'anything');
    });

    test('a cell actually holding bytes is never offered for editing', () {
      // Which is why the affinity does not need to refuse: encodeCell marks a
      // real blob read-only, so no editor opens for one in the first place.
      expect(encodeCell(Uint8List(16)).editable, isFalse);
    });
  });

  group('the wire estimate', () {
    // The budget only works if it counts what the socket counts. Dart strings
    // are UTF-16 code units, so String.length undercounts every non-ASCII
    // character — and an oversized frame does not fail the query, it trips the
    // server's read limit and ends the live session for everyone watching.
    int costOf(String s) => approximateBytes([CellValue(s)]);

    test('non-ASCII text is charged its real UTF-8 size', () {
      // Three bytes per character, one UTF-16 unit each.
      final cjk = '実験' * 100;
      expect(cjk.length, 200);
      expect(costOf(cjk), greaterThanOrEqualTo(600), reason: 'charged UTF-16 units, not bytes');
    });

    test('an emoji is charged four bytes, not two', () {
      final emoji = '🙂' * 50;
      expect(emoji.length, 100, reason: 'each is a surrogate pair');
      expect(costOf(emoji), greaterThanOrEqualTo(200));
    });

    test('JSON escaping is charged', () {
      // A column holding stringified JSON is the common case: every quote
      // becomes two bytes on the wire.
      final quoted = '"' * 100;
      expect(costOf(quoted), greaterThanOrEqualTo(200));
    });

    test('the estimate is never under what jsonEncode actually produces', () {
      for (final s in ['plain ascii', '実験データ', '🙂🙂🙂', '{"a":"b"}', 'tab\there']) {
        final actual = utf8.encode(jsonEncode(s)).length;
        expect(costOf(s), greaterThanOrEqualTo(actual),
            reason: 'underestimated $s: budget ${costOf(s)}, real $actual');
      }
    });

    test('a page of CJK stops well inside the frame the socket accepts', () async {
      // The concrete failure: five wide text columns of CJK passed the budget
      // at roughly a third of their true size, and the frame that reached the
      // server was over its one megabyte read limit.
      await db.execute('CREATE TABLE wide (k TEXT, a TEXT, b TEXT, c TEXT, d TEXT)');
      final big = '実' * (maxCellChars - 1);
      for (var i = 0; i < 60; i++) {
        await db.insert('wide', {'k': 'r$i', 'a': big, 'b': big, 'c': big, 'd': big});
      }

      final page = await source.read(const CodeScoutReadRequest(namespace: 'wide', limit: 100));
      final encoded = utf8.encode(jsonEncode(page.toJson())).length;

      expect(page.stoppedForSize, isTrue);
      expect(encoded, lessThan(1024 * 1024),
          reason: 'the frame is over the socket read limit, which drops the session');
    });
  });

  group('cells', () {
    test('a blob travels as its size, never as its bytes', () {
      final cell = encodeCell(Uint8List(43111));
      expect(cell.display, '<blob · 42.1 KB>');
      expect(cell.editable, isFalse);
    });

    test('an over-long string is summarised and locked', () {
      // The rule across the feature: the dashboard may only edit what it
      // actually saw. A truncated value fails that, so it is read-only for the
      // same reason a blob is.
      final cell = encodeCell('x' * (maxCellChars + 500));
      expect((cell.display as String).length, maxCellChars + 1);
      expect(cell.editable, isFalse);
      expect(cell.because, isNotNull);
    });

    test('a redacted column never carries its value', () {
      final cell = encodeCell('the-real-token', redacted: true);
      expect(cell.display, '[redacted]');
      expect(cell.display, isNot(contains('real-token')));
      expect(cell.editable, isFalse);
    });

    test('ordinary values travel as themselves', () {
      expect(encodeCell(42).display, 42);
      expect(encodeCell(1.5).display, 1.5);
      expect(encodeCell('hi').display, 'hi');
      expect(encodeCell(null).display, isNull);
    });
  });

  group('read', () {
    test('rows come back with their handles', () async {
      final page = await source.read(const CodeScoutReadRequest(namespace: 'flags'));
      expect(page.rows, hasLength(3));
      expect(page.handles, hasLength(3));
      expect(page.handles.every((h) => h is int), isTrue);
    });

    test('a view has no handles, so nothing there can be addressed', () async {
      final page = await source.read(const CodeScoutReadRequest(namespace: 'v_flags'));
      expect(page.rows, isNotEmpty);
      expect(page.handles.every((h) => h == null), isTrue);
    });

    test('sorting uses the column asked for', () async {
      final page = await source.read(
        const CodeScoutReadRequest(namespace: 'flags', sortColumn: 'key'),
      );
      final keys = page.rows.map((r) => r.first.display).toList();
      expect(keys, ['checkout_one_tap', 'checkout_v2', 'search_beta']);
    });

    test('descending reverses it', () async {
      final page = await source.read(
        const CodeScoutReadRequest(namespace: 'flags', sortColumn: 'key', descending: true),
      );
      expect(page.rows.first.first.display, 'search_beta');
    });

    test('a sort column that is not in the schema is refused', () async {
      // The security argument in one test. The dashboard cannot name anything
      // the table does not have, so there is nothing to smuggle in.
      expect(
        () => source.read(const CodeScoutReadRequest(
            namespace: 'flags', sortColumn: 'key FROM flags; DROP TABLE flags;--')),
        throwsA(isA<ArgumentError>()),
      );
      // And the table is still there.
      expect((await db.rawQuery('SELECT count(*) c FROM flags')).first['c'], 3);
    });

    test('a filter column that is not in the schema is refused', () async {
      expect(
        () => source.read(const CodeScoutReadRequest(
            namespace: 'flags', filters: {'nope): --': 'x'})),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('filters match a contained substring', () async {
      final page = await source.read(
        const CodeScoutReadRequest(namespace: 'flags', filters: {'key': 'checkout'}),
      );
      expect(page.rows, hasLength(2));
    });

    test('filtering a number works the way somebody typing it expects', () async {
      final page = await source.read(
        const CodeScoutReadRequest(namespace: 'flags', filters: {'enabled': '1'}),
      );
      expect(page.rows, hasLength(1));
      expect(page.rows.first.first.display, 'checkout_one_tap');
    });

    test("LIKE's wildcards mean themselves in a filter", () async {
      // Somebody filtering by "100%" wants rows containing that string, not
      // every row with a 1 followed by two zeroes and anything at all.
      await db.insert('flags', {'key': 'discount_100%', 'enabled': 0});
      await db.insert('flags', {'key': 'discount_100x', 'enabled': 0});

      final page = await source.read(
        const CodeScoutReadRequest(namespace: 'flags', filters: {'key': '100%'}),
      );
      expect(page.rows, hasLength(1));
      expect(page.rows.single.first.display, 'discount_100%');
    });

    test('an empty filter is not a filter', () async {
      final page = await source.read(
        const CodeScoutReadRequest(namespace: 'flags', filters: {'key': ''}),
      );
      expect(page.rows, hasLength(3));
    });

    test('paging reports whether there is more', () async {
      final first = await source.read(
        const CodeScoutReadRequest(namespace: 'flags', limit: 2, sortColumn: 'key'),
      );
      expect(first.rows, hasLength(2));
      expect(first.hasMore, isTrue);

      final second = await source.read(
        const CodeScoutReadRequest(namespace: 'flags', limit: 2, offset: 2, sortColumn: 'key'),
      );
      expect(second.rows, hasLength(1));
      expect(second.hasMore, isFalse);
    });

    test("the row ceiling is the device's, not the dashboard's", () async {
      // A limit the caller can raise is not a limit. Only the device knows what
      // it costs to build the page.
      for (var i = 0; i < 150; i++) {
        await db.insert('flags', {'key': 'f$i', 'enabled': 0});
      }
      final page = await source.read(
        const CodeScoutReadRequest(namespace: 'flags', limit: 100000),
      );
      expect(page.rows.length, maxPageRows);
      expect(page.hasMore, isTrue);
    });

    test('a page stops before it grows into a frame the socket would drop', () async {
      // A cache table with several large text columns, which is the shape that
      // actually gets near the limit: one big column across the full 100 rows
      // does not, so a test built on one would pass whatever the budget was.
      await db.execute('CREATE TABLE cache (k TEXT, a TEXT, b TEXT, c TEXT, d TEXT)');
      final big = 'y' * (maxCellChars - 1);
      for (var i = 0; i < 60; i++) {
        await db.insert('cache', {'k': 'r$i', 'a': big, 'b': big, 'c': big, 'd': big});
      }

      final page = await source.read(
        const CodeScoutReadRequest(namespace: 'cache', limit: 100),
      );

      // Overshooting kills the whole live stream rather than this one query,
      // so stopping early and saying so is the only safe answer.
      expect(page.stoppedForSize, isTrue);
      expect(page.hasMore, isTrue);
      expect(page.rows.length, lessThan(60));
      expect(page.rows, isNotEmpty, reason: 'a budget that returns nothing is not a budget');
    });

    test('a redacted column is redacted in the rows, not just flagged', () async {
      // The flag on the column is a rendering hint. This is the protection.
      await CodeScout.instance.init(
        configuration: CodeScoutConfiguration(
          redaction: const RedactionBehavior(bodyKeys: {'note'}),
        ),
      );
      addTearDown(CodeScout.instance.dispose);

      final page = await source.read(const CodeScoutReadRequest(namespace: 'flags'));
      final noteIndex = page.columns.indexWhere((c) => c.name == 'note');
      for (final row in page.rows) {
        expect(row[noteIndex].display, anyOf('[redacted]', isNull));
        expect(row[noteIndex].display, isNot('staged'));
      }
    });
  });

  group('write', () {
    test('a cell changes', () async {
      final id = await rowidOf('checkout_v2');
      final result = await source.write(CodeScoutWriteRequest(
        namespace: 'flags', column: 'enabled', handle: id, value: '1', was: 0,
      ));

      expect(result.ok, isTrue);
      final now = await db.rawQuery('SELECT enabled FROM flags WHERE rowid = ?', [id]);
      expect(now.first['enabled'], 1);
    });

    test('the stored value has the column\'s type', () async {
      final id = await rowidOf('checkout_v2');
      await source.write(CodeScoutWriteRequest(
        namespace: 'flags', column: 'enabled', handle: id, value: '1', was: 0,
      ));
      final now = await db.rawQuery('SELECT typeof(enabled) t FROM flags WHERE rowid = ?', [id]);
      expect(now.first['t'], 'integer');
    });

    test('a value SQLite would store as the wrong type never reaches it', () async {
      // This is what coercion is actually for, and it took removing it to find
      // out. SQLite converts well-formed numeric text itself, so binding "1" to
      // an INTEGER column stores the integer 1 with or without our help.
      // "banana" is the case it does not convert: it stores the *text*, and the
      // app then reads a String where it expects an int.
      final id = await rowidOf('checkout_v2');
      final result = await source.write(CodeScoutWriteRequest(
        namespace: 'flags', column: 'enabled', handle: id, value: 'banana', was: 0,
      ));

      expect(result.ok, isFalse);
      final now = await db.rawQuery('SELECT typeof(enabled) t FROM flags WHERE rowid = ?', [id]);
      expect(now.first['t'], 'integer',
          reason: 'text landed in an INTEGER column, which is the corruption this prevents');
    });

    test('a row the app changed first is refused, and nothing is written', () async {
      final id = await rowidOf('checkout_v2');
      // The app gets there first.
      await db.rawUpdate('UPDATE flags SET enabled = 5 WHERE rowid = ?', [id]);

      final result = await source.write(CodeScoutWriteRequest(
        namespace: 'flags', column: 'enabled', handle: id, value: '1', was: 0,
      ));

      expect(result.ok, isFalse);
      expect(result.code, 'row_changed');
      expect(result.current, 5);

      final now = await db.rawQuery('SELECT enabled FROM flags WHERE rowid = ?', [id]);
      expect(now.first['enabled'], 5, reason: 'the write went through anyway');
    });

    test('a row that is gone is told apart from one that changed', () async {
      final id = await rowidOf('checkout_v2');
      await db.rawDelete('DELETE FROM flags WHERE rowid = ?', [id]);

      final result = await source.write(CodeScoutWriteRequest(
        namespace: 'flags', column: 'enabled', handle: id, value: '1', was: 0,
      ));
      expect(result.code, 'row_gone');
    });

    test('a null old value still matches, because IS is not =', () async {
      // `note` is null on this row. With `= ?` the comparison is never true and
      // the cell could never be edited, which would look like a broken button
      // rather than a rule.
      final id = await rowidOf('checkout_one_tap');
      final result = await source.write(CodeScoutWriteRequest(
        namespace: 'flags', column: 'note', handle: id, value: 'now set', was: null,
      ));
      expect(result.ok, isTrue);
    });

    test('a value can be set back to NULL', () async {
      final id = await rowidOf('checkout_v2');
      final result = await source.write(CodeScoutWriteRequest(
        namespace: 'flags', column: 'note', handle: id, value: null, was: 'staged',
      ));
      expect(result.ok, isTrue);
      final now = await db.rawQuery('SELECT note FROM flags WHERE rowid = ?', [id]);
      expect(now.first['note'], isNull);
    });

    test('a NOT NULL column will not take a null', () async {
      final id = await rowidOf('checkout_v2');
      final result = await source.write(CodeScoutWriteRequest(
        namespace: 'flags', column: 'key', handle: id, value: null, was: 'checkout_v2',
      ));
      expect(result.ok, isFalse);
      expect(result.message, contains('cannot be empty'));
    });

    test('a value that will not coerce is refused with a reason', () async {
      final id = await rowidOf('checkout_v2');
      final result = await source.write(CodeScoutWriteRequest(
        namespace: 'flags', column: 'enabled', handle: id, value: 'banana', was: 0,
      ));
      expect(result.ok, isFalse);
      expect(result.message, contains('whole number'));
    });

    test('a column that is not in the schema is refused', () async {
      final id = await rowidOf('checkout_v2');
      final result = await source.write(CodeScoutWriteRequest(
        namespace: 'flags', column: 'enabled = 1, key', handle: id, value: 'x', was: 0,
      ));
      expect(result.ok, isFalse);
      expect(result.message, contains('no column'));
      expect((await db.rawQuery('SELECT key FROM flags WHERE rowid = ?', [id])).first['key'],
          'checkout_v2');
    });

    test('a view cannot be written to', () async {
      final result = await source.write(const CodeScoutWriteRequest(
        namespace: 'v_flags', column: 'key', handle: 1, value: 'x', was: 'y',
      ));
      expect(result.ok, isFalse);
      expect(result.message, contains('read but not changed'));
    });

    test('a redacted column cannot be written', () async {
      await CodeScout.instance.init(
        configuration: CodeScoutConfiguration(
          redaction: const RedactionBehavior(bodyKeys: {'note'}),
        ),
      );
      addTearDown(CodeScout.instance.dispose);

      final id = await rowidOf('checkout_v2');
      final result = await source.write(CodeScoutWriteRequest(
        namespace: 'flags', column: 'note', handle: id, value: 'x', was: '[redacted]',
      ));
      expect(result.ok, isFalse);
      expect(result.message, contains('redacted'));
    });
  });

  group('the registry enforces writable', () {
    test('a source registered for browsing refuses a write', () async {
      // Without this the flag is decoration: a database exposed to look at
      // would be exactly as editable as one exposed to edit, and the only
      // difference would be what the dashboard chose to draw.
      DatabaseRegistry.i.register('ro', source);
      final id = await rowidOf('checkout_v2');

      final result = await DatabaseRegistry.i.write(
        'ro',
        CodeScoutWriteRequest(
            namespace: 'flags', column: 'enabled', handle: id, value: '1', was: 0),
      );

      expect(result.ok, isFalse);
      expect(result.message, contains('browsing only'));
      final now = await db.rawQuery('SELECT enabled FROM flags WHERE rowid = ?', [id]);
      expect(now.first['enabled'], 0, reason: 'a read-only source was written to');
    });

    test('a writable source goes through', () async {
      DatabaseRegistry.i.register('rw', source, writable: true);
      final id = await rowidOf('checkout_v2');

      final result = await DatabaseRegistry.i.write(
        'rw',
        CodeScoutWriteRequest(
            namespace: 'flags', column: 'enabled', handle: id, value: '1', was: 0),
      );
      expect(result.ok, isTrue);
    });

    test('reading an unregistered name is an error', () {
      expect(
        () => DatabaseRegistry.i.read('nope', const CodeScoutReadRequest(namespace: 'flags')),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
