import 'dart:convert';

import 'package:code_scout/src/db/db_source.dart';
import 'package:code_scout/src/db/db_value.dart';
import 'package:code_scout/src/utils/redactor.dart';

/// Reads the keys in one namespace.
typedef KeyLister = Future<Iterable<String>> Function();

/// Reads one value.
typedef KeyReader = Future<Object?> Function(String key);

/// Writes one value. Null means the caller asked to clear it.
typedef KeyWriter = Future<void> Function(String key, Object? value);

/// Browses anything shaped like keys and values.
///
/// Takes functions rather than a `SharedPreferences` or a Hive `Box`, and that
/// is the whole design. Naming either type would put its package in the
/// dependency tree of every app that installs Code Scout, for a feature that
/// only runs in debug. Four lines in an app costs nothing; a dependency costs
/// everybody.
///
/// ```dart
/// CodeScout.instance.registerDatabase(
///   'prefs',
///   CodeScoutKeyValue(
///     keys: () async => prefs.getKeys(),
///     readKey: (k) async => prefs.get(k),
///     writeKey: (k, v) async => v == null
///         ? prefs.remove(k)
///         : prefs.setString(k, '$v'),
///   ),
///   writable: kDebugMode,
/// );
/// ```
///
/// The dashboard renders this in the same grid as a table, with two columns and
/// the key as the row handle. One grid, one editor, one code path.
class CodeScoutKeyValue implements CodeScoutSource {
  CodeScoutKeyValue({
    required this.keys,
    required this.readKey,
    this.writeKey,
    this.namespace = 'keys',
  }) : _namespaces = null;

  /// Several named collections in one source, which is what Hive gives you: a
  /// box per name. Each is listed like a table.
  CodeScoutKeyValue.namespaces(Map<String, CodeScoutKeyValue> namespaces)
      : keys = _noKeys,
        readKey = _noRead,
        writeKey = null,
        namespace = '',
        _namespaces = namespaces;

  final KeyLister keys;
  final KeyReader readKey;

  /// Null for a source that can only be read. Note this is separate from the
  /// `writable` flag on registration: this says the store *can* be written, the
  /// flag says the app agreed that it may be.
  final KeyWriter? writeKey;

  final String namespace;
  final Map<String, CodeScoutKeyValue>? _namespaces;

  static Future<Iterable<String>> _noKeys() async => const [];
  static Future<Object?> _noRead(String _) async => null;

  @override
  CodeScoutSourceKind get kind => CodeScoutSourceKind.keyValue;

  @override
  Future<List<CodeScoutNamespace>> namespaces() async {
    final grouped = _namespaces;
    if (grouped == null) {
      return [CodeScoutNamespace(name: namespace, kind: CodeScoutNamespaceKind.box)];
    }
    return [
      for (final name in grouped.keys)
        CodeScoutNamespace(name: name, kind: CodeScoutNamespaceKind.box),
    ];
  }

  /// Two columns, always. `key` is the row handle and cannot be renamed from
  /// here — renaming a key is deleting one and creating another, which is a
  /// different operation with a different blast radius.
  @override
  Future<CodeScoutSchema> describe(String namespace) async {
    final target = _resolve(namespace);
    return CodeScoutSchema(
      namespace: namespace,
      columns: const [
        CodeScoutColumn(name: 'key', declaredType: 'TEXT', notNull: true, primaryKey: true),
        CodeScoutColumn(name: 'value', declaredType: ''),
      ],
      rowHandle: target.writeKey == null ? null : 'key',
      readOnlyBecause: target.writeKey == null
          ? 'This store was registered without a way to write to it.'
          : null,
    );
  }

  @override
  Future<CodeScoutPage> read(CodeScoutReadRequest request) async {
    final target = _resolve(request.namespace);

    // Every column is checked for membership before it is used, the same as
    // the SQL side does against PRAGMA table_info. A key-value store has
    // exactly two, and silently ignoring an unknown one told the dashboard its
    // sort had been applied when nothing had happened.
    const known = {'key', 'value'};
    final sort = request.sortColumn;
    if (sort != null && !known.contains(sort)) {
      throw ArgumentError.value(sort, 'sortColumn', 'no such column in ${request.namespace}');
    }
    for (final column in request.filters.keys) {
      if (!known.contains(column)) {
        throw ArgumentError.value(column, 'filter', 'no such column in ${request.namespace}');
      }
    }

    var names = (await target.keys()).toList()..sort();

    // Filtering and sorting happen here rather than in a query, because there
    // is no query: a key-value store hands over its keys and that is the whole
    // interface it has.
    final keyFilter = request.filters['key'];
    if (keyFilter != null && keyFilter.isNotEmpty) {
      final needle = keyFilter.toLowerCase();
      names = names.where((k) => k.toLowerCase().contains(needle)).toList();
    }

    final valueFilter = request.filters['value'];
    final limit = request.limit.clamp(1, 500);
    final offset = request.offset < 0 ? 0 : request.offset;

    // Every value is read before any page is cut, because both sorting by value
    // and filtering by it need the whole set to be correct. That is one read
    // per key over a store the SDK caps at 500 rows a page — a preferences file
    // or a Hive box, not a table. Sorting the page rather than the set would
    // order whichever rows happened to be first, which is the kind of wrong
    // that looks right.
    final pairs = <({String key, String value})>[];
    for (final key in names) {
      final rendered = _stringify(await target.readKey(key));
      if (valueFilter != null && valueFilter.isNotEmpty) {
        if (!rendered.toLowerCase().contains(valueFilter.toLowerCase())) continue;
      }
      pairs.add((key: key, value: rendered));
    }

    if (sort == 'value') {
      pairs.sort((a, b) => a.value.compareTo(b.value));
    }
    // Keys are already ascending from the sort above; anything else is either
    // sort == 'key' or no sort at all, which are the same order.
    if (request.descending) {
      final reversed = pairs.reversed.toList();
      pairs
        ..clear()
        ..addAll(reversed);
    }

    final rows = <List<CellValue>>[];
    final handles = <Object?>[];
    var bytes = 0;
    var stoppedForSize = false;
    var more = false;

    for (var i = offset; i < pairs.length; i++) {
      if (rows.length >= limit) {
        more = true;
        break;
      }
      final pair = pairs[i];

      final cells = [
        // The key is the handle, so it is never editable: changing it would be
        // a delete and an insert wearing one button.
        CellValue(pair.key,
            editable: false, because: 'A key is the row itself, not a value in it.'),
        encodeCell(pair.value, redacted: Redactor.hides(pair.key)),
      ];

      final size = approximateBytes(cells);
      if (rows.isNotEmpty && bytes + size > maxPageBytes) {
        stoppedForSize = true;
        break;
      }
      bytes += size;
      rows.add(cells);
      handles.add(pair.key);
    }

    return CodeScoutPage(
      columns: (await describe(request.namespace)).columns,
      rows: rows,
      handles: handles,
      hasMore: more || stoppedForSize,
      stoppedForSize: stoppedForSize,
    );
  }

  @override
  Future<CodeScoutWriteResult> write(CodeScoutWriteRequest request) async {
    final target = _resolve(request.namespace);
    final writer = target.writeKey;
    if (writer == null) {
      return const CodeScoutWriteResult.refused(
          'This store was registered without a way to write to it.');
    }
    if (request.column != 'value') {
      return const CodeScoutWriteResult.refused(
          'Only the value can be changed. Renaming a key is a delete and an insert, '
          'which this does not do.');
    }

    final key = request.handle?.toString();
    if (key == null) {
      return const CodeScoutWriteResult.refused('No key was named.');
    }
    if (Redactor.hides(key)) {
      return const CodeScoutWriteResult.refused(
          'This key is redacted, so there is nothing to compare against.');
    }

    // The same conflict check the SQL side does, done by hand because there is
    // no WHERE to hang it on: read what is there now and compare it with what
    // the dashboard was shown.
    final current = _stringify(await target.readKey(key));
    final was = request.was?.toString() ?? '';
    if (current != was) {
      return CodeScoutWriteResult.rowChanged(current);
    }

    await writer(key, request.value);
    return const CodeScoutWriteResult.written();
  }

  CodeScoutKeyValue _resolve(String namespace) {
    final grouped = _namespaces;
    if (grouped == null) return this;
    final found = grouped[namespace];
    if (found == null) {
      throw ArgumentError.value(namespace, 'namespace', 'no such collection');
    }
    return found;
  }

  /// Everything renders as text, because that is what a key-value store hands
  /// back: a bool, an int, a `List<String>`, or a JSON blob somebody stringified.
  /// A list is encoded rather than printed with Dart's toString so what appears
  /// is valid JSON rather than `[a, b]`.
  static String _stringify(Object? raw) {
    if (raw == null) return '';
    if (raw is String) return raw;
    if (raw is num || raw is bool) return '$raw';
    try {
      return jsonEncode(raw);
    } catch (_) {
      return '$raw';
    }
  }
}
