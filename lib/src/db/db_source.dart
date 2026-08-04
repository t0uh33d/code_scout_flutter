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

/// Something Code Scout can browse on the device.
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
}
