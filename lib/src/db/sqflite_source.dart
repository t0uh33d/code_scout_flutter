import 'package:code_scout/src/db/db_source.dart';
import 'package:code_scout/src/utils/redactor.dart';
import 'package:sqflite/sqflite.dart';

/// Quotes an identifier for use in SQL.
///
/// Every identifier that reaches here came out of `sqlite_master` or
/// `PRAGMA table_info`, so this is not a defence against injection — the
/// dashboard never sends SQL, and a name it does send is checked against the
/// real schema before anything is built from it. This is so a table called
/// `order` or `my table` works at all.
String quoteIdentifier(String id) => '"${id.replaceAll('"', '""')}"';

/// Browses a SQLite database through the connection your app already has.
///
/// Taking the open [Database] rather than the file path is deliberate: WAL,
/// SQLCipher and attached databases all keep working with no special handling,
/// because this is the same connection the app itself reads through.
///
/// ```dart
/// await CodeScout.instance.registerDatabase(
///   'shop.db',
///   CodeScoutSqflite(db),
///   writable: kDebugMode,
/// );
/// ```
class CodeScoutSqflite implements CodeScoutSource {
  const CodeScoutSqflite(this.db);

  final DatabaseExecutor db;

  @override
  CodeScoutSourceKind get kind => CodeScoutSourceKind.sql;

  @override
  Future<List<CodeScoutNamespace>> namespaces() async {
    // sqlite_% is SQLite's own bookkeeping: sqlite_sequence, sqlite_stat1 and
    // friends. Listing them would offer a developer a table they did not make
    // and cannot usefully read.
    final rows = await db.rawQuery(
      "SELECT name, type FROM sqlite_master "
      "WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' "
      "ORDER BY type, name",
    );

    return rows
        .map((r) => CodeScoutNamespace(
              name: r['name'] as String,
              kind: r['type'] == 'view'
                  ? CodeScoutNamespaceKind.view
                  : CodeScoutNamespaceKind.table,
            ))
        .toList();
  }

  @override
  Future<CodeScoutSchema> describe(String namespace) async {
    final info = await db.rawQuery('PRAGMA table_info(${quoteIdentifier(namespace)})');
    if (info.isEmpty) {
      throw ArgumentError.value(namespace, 'namespace', 'no such table or view');
    }

    final columns = info
        .map((c) {
          final name = c['name'] as String;
          return CodeScoutColumn(
            name: name,
            declaredType: (c['type'] as String?) ?? '',
            notNull: (c['notnull'] as int? ?? 0) != 0,
            primaryKey: (c['pk'] as int? ?? 0) != 0,
            redacted: Redactor.hides(name),
          );
        })
        .toList();

    final handle = await _rowHandle(namespace);

    return CodeScoutSchema(
      namespace: namespace,
      columns: columns,
      rowHandle: handle.column,
      readOnlyBecause: handle.because,
    );
  }

  /// Finds something that identifies a row, by asking SQLite rather than by
  /// reading the schema text.
  ///
  /// `LIMIT 0` runs the query planner and returns nothing, so this costs a
  /// prepare and no rows. It answers definitively for both cases that have no
  /// rowid — a view, and a WITHOUT ROWID table — where parsing `sqlite_master`
  /// for the words "WITHOUT ROWID" would be fooled by a comment or by a column
  /// that happens to be called that.
  Future<({String? column, String? because})> _rowHandle(String namespace) async {
    try {
      await db.rawQuery('SELECT rowid FROM ${quoteIdentifier(namespace)} LIMIT 0');
      return (column: 'rowid', because: null);
    } catch (_) {
      // Both remaining cases are genuinely unaddressable with a single column.
      // A WITHOUT ROWID table has a primary key that could serve, but it may be
      // several columns, and a composite handle changes the shape of every
      // update. Not worth carrying until somebody has one.
      return (
        column: null,
        because: 'Rows here have no single column that identifies them, '
            'so their values can be read but not changed.',
      );
    }
  }
}
