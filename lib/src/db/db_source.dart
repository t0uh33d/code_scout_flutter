import 'package:code_scout/src/db/db_value.dart';

/// What kind of store is behind a registered source.
///
/// The dashboard renders both in the same grid: a key-value store is shown as a
/// two-column table whose row handle is the key. One grid, one editor, one code
/// path, rather than a second screen for the half of the ecosystem that is not
/// SQL.
enum CodeScoutSourceKind {
  /// Real tables and columns, read with SQL.
  sql,

  /// Named keys and values. `shared_preferences`, Hive, and anything shaped
  /// like them.
  keyValue,
}

/// What a namespace is, so the dashboard can say why some of them cannot be
/// edited without having to guess from a failure.
enum CodeScoutNamespaceKind { table, view, box }

/// One browsable collection inside a source: a table, a view, or a box.
class CodeScoutNamespace {
  const CodeScoutNamespace({required this.name, required this.kind});

  final String name;
  final CodeScoutNamespaceKind kind;

  Map<String, dynamic> toJson() => {'name': name, 'kind': kind.name};
}

/// One column, as the dashboard needs to render it.
class CodeScoutColumn {
  const CodeScoutColumn({
    required this.name,
    this.declaredType = '',
    this.notNull = false,
    this.primaryKey = false,
    this.redacted = false,
  });

  final String name;

  /// SQLite's declared type, which may be empty: columns can be declared with
  /// no type at all, and affinity is a suggestion rather than a rule. Carried
  /// so a value can be coerced back to what the column expects before a write,
  /// because storing "42" as text in an INTEGER column is how you make an app
  /// crash reading its own data.
  final String declaredType;

  final bool notNull;
  final bool primaryKey;

  /// True when the redaction config names this column.
  ///
  /// This is a rendering hint, not the protection. The real value is replaced
  /// where rows are read, on the device, so a redacted column has nothing to
  /// leak whatever the dashboard does with this flag.
  final bool redacted;

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': declaredType,
        'not_null': notNull,
        'primary_key': primaryKey,
        'redacted': redacted,
      };
}

/// The shape of one namespace, and whether its rows can be addressed.
class CodeScoutSchema {
  const CodeScoutSchema({
    required this.namespace,
    required this.columns,
    this.rowHandle,
    this.readOnlyBecause,
  });

  final String namespace;
  final List<CodeScoutColumn> columns;

  /// The column that identifies a row for an update, or null when there is
  /// none. `rowid` for an ordinary SQLite table, the key for a key-value store.
  final String? rowHandle;

  /// Why this namespace cannot be edited, in words meant for a person. Set
  /// exactly when [rowHandle] is null.
  ///
  /// Saying so up front is the point: a cell that silently refuses to save
  /// reads as a bug, and one that explains itself reads as a boundary.
  final String? readOnlyBecause;

  bool get editable => rowHandle != null;

  Map<String, dynamic> toJson() => {
        'namespace': namespace,
        'columns': columns.map((c) => c.toJson()).toList(),
        'row_handle': rowHandle,
        'read_only_because': readOnlyBecause,
      };
}

/// A page of rows to fetch.
///
/// Structure, never SQL. The dashboard names a table, a page, a sort and some
/// filters; the device builds the statement. That is what makes read-only a
/// property of the code rather than a rule somebody has to enforce, because no
/// other statement can be constructed from these fields.
class CodeScoutReadRequest {
  const CodeScoutReadRequest({
    required this.namespace,
    this.limit = 100,
    this.offset = 0,
    this.sortColumn,
    this.descending = false,
    this.filters = const {},
  });

  final String namespace;
  final int limit;
  final int offset;

  /// Must name a real column, checked against the schema before use.
  final String? sortColumn;
  final bool descending;

  /// Column name to the text typed under it. Matched as a contained substring,
  /// one rule for every type, because the alternative is an expression language
  /// and therefore a parser on the device.
  final Map<String, String> filters;

  factory CodeScoutReadRequest.fromJson(Map<String, dynamic> j) => CodeScoutReadRequest(
        namespace: j['namespace'] as String,
        limit: (j['limit'] as num?)?.toInt() ?? 100,
        offset: (j['offset'] as num?)?.toInt() ?? 0,
        sortColumn: j['sort'] as String?,
        descending: j['desc'] as bool? ?? false,
        filters: (j['filters'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? const {},
      );
}

/// One page of rows.
class CodeScoutPage {
  const CodeScoutPage({
    required this.columns,
    required this.rows,
    required this.handles,
    required this.hasMore,
    this.stoppedForSize = false,
    this.rowHandle,
    this.kind = CodeScoutSourceKind.sql,
  });

  final List<CodeScoutColumn> columns;

  /// Row-major, parallel to [columns]. Lists rather than maps because the
  /// column names are already in the header and repeating them on every row is
  /// most of the bytes in a page.
  final List<List<CellValue>> rows;

  /// What identifies each row, parallel to [rows]. Null throughout when the
  /// namespace has no row handle.
  final List<Object?> handles;

  final bool hasMore;

  /// The column that identifies a row: `rowid` for an ordinary SQLite table,
  /// `key` for a key-value store, null when nothing does. Carried on the page
  /// so the dashboard can name it without a second round trip — it shows the
  /// statement a write will run, and a preview naming the wrong column is
  /// worse than no preview at all.
  final String? rowHandle;

  /// Which kind of store this page came from. A key-value write runs no SQL,
  /// so the dashboard describes it differently.
  final CodeScoutSourceKind kind;

  /// True when the page ended because it was getting too big to send, rather
  /// than because the rows ran out. Said out loud because a page that quietly
  /// stops short reads as "that is all there is".
  final bool stoppedForSize;

  Map<String, dynamic> toJson() => {
        'columns': columns.map((c) => c.toJson()).toList(),
        'rows': rows.map((r) => r.map((c) => c.toJson()).toList()).toList(),
        'handles': handles,
        'has_more': hasMore,
        'stopped_for_size': stoppedForSize,
        'row_handle': rowHandle,
        'kind': kind.name,
      };
}

/// A change to exactly one cell.
///
/// One column, one row, one value. There is no shape here that can express
/// anything wider, which is the point: an UPDATE with no WHERE cannot be
/// requested because there is nowhere to put it.
class CodeScoutWriteRequest {
  const CodeScoutWriteRequest({
    required this.namespace,
    required this.column,
    required this.handle,
    required this.value,
    required this.was,
  });

  final String namespace;
  final String column;

  /// The row handle's value, usually a rowid.
  final Object? handle;

  /// What to store, as typed. Null means SQL NULL.
  final String? value;

  /// The value the dashboard was displaying, carried so a row the app has
  /// changed underneath rejects the write instead of being overwritten.
  final Object? was;

  factory CodeScoutWriteRequest.fromJson(Map<String, dynamic> j) => CodeScoutWriteRequest(
        namespace: j['namespace'] as String,
        column: j['column'] as String,
        handle: j['handle'],
        value: j['value'] as String?,
        was: j['was'],
      );
}

/// How a write went.
class CodeScoutWriteResult {
  const CodeScoutWriteResult._(this.ok, {this.code, this.message, this.current});

  const CodeScoutWriteResult.written() : this._(true);

  /// The row is there but does not hold what the dashboard was shown, so the
  /// app changed it first. Nothing was written, and [current] is what it holds
  /// now.
  const CodeScoutWriteResult.rowChanged(Object? current)
      : this._(false, code: 'row_changed', current: current);

  const CodeScoutWriteResult.rowGone()
      : this._(false,
            code: 'row_gone', message: 'That row is no longer in the table.');

  const CodeScoutWriteResult.refused(String why)
      : this._(false, code: 'refused', message: why);

  final bool ok;
  final String? code;
  final String? message;
  final Object? current;

  Map<String, dynamic> toJson() => {
        'ok': ok,
        if (code != null) 'code': code,
        if (message != null) 'message': message,
        if (current != null) 'current': current,
      };
}

/// Something CodeScout can browse on the device.
///
/// Implement this to expose a store the built-in adapters do not cover. Nothing
/// is browsable until an app registers it, so this is only ever reached for a
/// store its developer named on purpose.
abstract class CodeScoutSource {
  CodeScoutSourceKind get kind;

  /// Every collection in this source. Names only: a hundred tables is a
  /// hundred rows in a list, and describing all of them up front would be a
  /// hundred round trips to SQLite for a screen showing one.
  Future<List<CodeScoutNamespace>> namespaces();

  /// The columns of one namespace, and whether its rows can be addressed.
  Future<CodeScoutSchema> describe(String namespace);

  /// One page of rows.
  Future<CodeScoutPage> read(CodeScoutReadRequest request);

  /// Changes one cell. Only ever reached for a source registered writable.
  Future<CodeScoutWriteResult> write(CodeScoutWriteRequest request);
}
