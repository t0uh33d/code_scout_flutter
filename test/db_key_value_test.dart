import 'package:code_scout/code_scout.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for shared_preferences, Hive, or anything else with a key and a
/// value. The adapter takes closures precisely so a test needs no plugin.
class _Store {
  _Store(this.values);
  final Map<String, Object?> values;

  CodeScoutKeyValue source({bool writable = true, String namespace = 'prefs'}) =>
      CodeScoutKeyValue(
        namespace: namespace,
        keys: () async => values.keys,
        readKey: (k) async => values[k],
        writeKey: writable
            ? (k, v) async {
                if (v == null) {
                  values.remove(k);
                } else {
                  values[k] = v;
                }
              }
            : null,
      );
}

void main() {
  late _Store store;

  setUp(() {
    store = _Store({
      'onboarding_done': true,
      'last_sync_ms': 1754301882431,
      'locale': 'en_GB',
      'recent_searches': ['shoes', 'socks'],
      'auth_token': 'tok_live_51H8xQ2',
    });
  });

  tearDown(DatabaseRegistry.i.clear);

  test('it reports itself as key-value, not SQL', () async {
    expect(store.source().kind, CodeScoutSourceKind.keyValue);
  });

  test('one store is one namespace', () async {
    final found = await store.source().namespaces();
    expect(found.single.name, 'prefs');
    expect(found.single.kind, CodeScoutNamespaceKind.box);
  });

  test('several boxes are listed like tables', () async {
    // What Hive gives you: a box per name, each browsable on its own.
    final grouped = CodeScoutKeyValue.namespaces({
      'settings': store.source(namespace: 'settings'),
      'cache': _Store({'a': 1}).source(namespace: 'cache'),
    });
    final names = (await grouped.namespaces()).map((n) => n.name);
    expect(names, containsAll(['settings', 'cache']));
  });

  test('the schema is two columns with the key as the handle', () async {
    final schema = await store.source().describe('prefs');
    expect(schema.columns.map((c) => c.name), ['key', 'value']);
    expect(schema.rowHandle, 'key');
    expect(schema.editable, isTrue);
  });

  test('a store with no writer is read only, and says why', () async {
    final schema = await store.source(writable: false).describe('prefs');
    expect(schema.editable, isFalse);
    expect(schema.readOnlyBecause, contains('without a way to write'));
  });

  group('reading', () {
    test('every key comes back as a row handled by its key', () async {
      final page = await store.source().read(const CodeScoutReadRequest(namespace: 'prefs'));
      expect(page.rows, hasLength(5));
      expect(page.handles, contains('locale'));
    });

    test('the key cell is never editable', () async {
      // Changing a key is a delete and an insert wearing one button, which is a
      // different operation with a different blast radius.
      final page = await store.source().read(const CodeScoutReadRequest(namespace: 'prefs'));
      expect(page.rows.every((r) => !r.first.editable), isTrue);
      expect(page.rows.first.first.because, contains('key is the row itself'));
    });

    test('a list is rendered as JSON rather than as Dart toString', () async {
      // `[shoes, socks]` is neither valid JSON nor copy-pasteable back in.
      final page = await store.source().read(const CodeScoutReadRequest(namespace: 'prefs'));
      final row = page.rows.firstWhere((r) => r.first.display == 'recent_searches');
      expect(row.last.display, '["shoes","socks"]');
    });

    test('bools and numbers survive as readable text', () async {
      final page = await store.source().read(const CodeScoutReadRequest(namespace: 'prefs'));
      final byKey = {for (final r in page.rows) r.first.display: r.last.display};
      expect(byKey['onboarding_done'], 'true');
      expect(byKey['last_sync_ms'], '1754301882431');
    });

    test('a redacted key never carries its value', () async {
      await CodeScout.instance.init(
        configuration: CodeScoutConfiguration(
          redaction: const RedactionBehavior(bodyKeys: {'auth_token'}),
        ),
      );
      addTearDown(CodeScout.instance.dispose);

      final page = await store.source().read(const CodeScoutReadRequest(namespace: 'prefs'));
      final row = page.rows.firstWhere((r) => r.first.display == 'auth_token');
      expect(row.last.display, '[redacted]');
      expect(row.last.display, isNot(contains('tok_live')));
      expect(row.last.editable, isFalse);
    });

    test('filtering matches on the key', () async {
      final page = await store.source().read(
            const CodeScoutReadRequest(namespace: 'prefs', filters: {'key': 'sync'}),
          );
      expect(page.rows, hasLength(1));
      expect(page.rows.single.first.display, 'last_sync_ms');
    });

    test('filtering matches on the value', () async {
      final page = await store.source().read(
            const CodeScoutReadRequest(namespace: 'prefs', filters: {'value': 'en_GB'}),
          );
      expect(page.rows, hasLength(1));
    });

    test('paging reports whether there is more', () async {
      final first = await store.source().read(
            const CodeScoutReadRequest(namespace: 'prefs', limit: 2),
          );
      expect(first.rows, hasLength(2));
      expect(first.hasMore, isTrue);

      final last = await store.source().read(
            const CodeScoutReadRequest(namespace: 'prefs', limit: 2, offset: 4),
          );
      expect(last.rows, hasLength(1));
      expect(last.hasMore, isFalse);
    });
  });

  group('writing', () {
    test('a value changes', () async {
      final result = await store.source().write(const CodeScoutWriteRequest(
        namespace: 'prefs', column: 'value', handle: 'locale', value: 'fr_FR', was: 'en_GB',
      ));
      expect(result.ok, isTrue);
      expect(store.values['locale'], 'fr_FR');
    });

    test('a value the app changed first is refused, and nothing is written', () async {
      // No WHERE to hang the check on, so it is done by hand: read what is
      // there now and compare it with what the dashboard was shown.
      store.values['locale'] = 'de_DE';

      final result = await store.source().write(const CodeScoutWriteRequest(
        namespace: 'prefs', column: 'value', handle: 'locale', value: 'fr_FR', was: 'en_GB',
      ));

      expect(result.ok, isFalse);
      expect(result.code, 'row_changed');
      expect(result.current, 'de_DE');
      expect(store.values['locale'], 'de_DE', reason: 'the write went through anyway');
    });

    test('clearing a value removes the key', () async {
      final result = await store.source().write(const CodeScoutWriteRequest(
        namespace: 'prefs', column: 'value', handle: 'locale', value: null, was: 'en_GB',
      ));
      expect(result.ok, isTrue);
      expect(store.values.containsKey('locale'), isFalse);
    });

    test('the key column cannot be written', () async {
      final result = await store.source().write(const CodeScoutWriteRequest(
        namespace: 'prefs', column: 'key', handle: 'locale', value: 'other', was: 'locale',
      ));
      expect(result.ok, isFalse);
      expect(result.message, contains('Only the value'));
    });

    test('a store with no writer refuses', () async {
      final result = await store.source(writable: false).write(const CodeScoutWriteRequest(
        namespace: 'prefs', column: 'value', handle: 'locale', value: 'x', was: 'en_GB',
      ));
      expect(result.ok, isFalse);
      expect(store.values['locale'], 'en_GB');
    });

    test('a redacted key cannot be written', () async {
      await CodeScout.instance.init(
        configuration: CodeScoutConfiguration(
          redaction: const RedactionBehavior(bodyKeys: {'auth_token'}),
        ),
      );
      addTearDown(CodeScout.instance.dispose);

      final result = await store.source().write(const CodeScoutWriteRequest(
        namespace: 'prefs', column: 'value', handle: 'auth_token',
        value: 'stolen', was: '[redacted]',
      ));
      expect(result.ok, isFalse);
      expect(store.values['auth_token'], 'tok_live_51H8xQ2');
    });
  });

  test('the registry enforces writable here too', () async {
    DatabaseRegistry.i.register('prefs', store.source());

    final result = await DatabaseRegistry.i.write(
      'prefs',
      const CodeScoutWriteRequest(
          namespace: 'prefs', column: 'value', handle: 'locale', value: 'fr_FR', was: 'en_GB'),
    );

    expect(result.ok, isFalse);
    expect(result.message, contains('browsing only'));
    expect(store.values['locale'], 'en_GB');
  });
}
