import 'package:code_scout/src/db/db_source.dart';
import 'package:code_scout/src/db/db_value.dart';
import 'package:code_scout/src/utils/redactor.dart';
import 'package:sqflite/sqflite.dart';

/// The alias the row handle is selected under.
///
/// Distinctive on purpose: `SELECT rowid, *` would collide with a real column
/// called rowid, and reading the wrong one would address the wrong row.
const String _handleAlias = '__cs_handle';

/// The most rows one page may hold, whatever was asked for.
///
/// Enforced here rather than trusted from the request. The device is the only
/// side that knows what it costs to build the page, and a limit the dashboard
/// could raise is not a limit.
const int maxPageRows = 100;

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

  @override
  Future<CodeScoutPage> read(CodeScoutReadRequest request) async {
    final schema = await describe(request.namespace);
    final byName = {for (final c in schema.columns) c.name: c};

    // Every identifier is checked for membership in the real schema. Not
    // escaped — checked. The dashboard cannot name a column that does not
    // exist, so there is nothing for it to smuggle in.
    final sort = request.sortColumn;
    if (sort != null && !byName.containsKey(sort)) {
      throw ArgumentError.value(sort, 'sortColumn', 'no such column in ${request.namespace}');
    }

    final where = <String>[];
    final args = <Object?>[];
    request.filters.forEach((column, text) {
      if (!byName.containsKey(column)) {
        throw ArgumentError.value(column, 'filter', 'no such column in ${request.namespace}');
      }
      if (text.isEmpty) return;
      // CAST so one rule covers every type: a number filtered by "42" behaves
      // the way the person typing it expects, with no per-type branching and
      // no expression language to parse.
      //
      // The typed text is escaped so % and _ mean the characters, not LIKE's
      // wildcards. Somebody filtering a discounts column by "100%" wants rows
      // containing that string, not every row.
      final escaped = text.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
      where.add("CAST(${quoteIdentifier(column)} AS TEXT) LIKE ? ESCAPE '\\'");
      args.add('%$escaped%');
    });

    final limit = request.limit.clamp(1, maxPageRows);
    final offset = request.offset < 0 ? 0 : request.offset;

    final selected = schema.columns.map((c) => quoteIdentifier(c.name)).join(', ');
    final projection =
        schema.rowHandle == null ? selected : '${schema.rowHandle} AS $_handleAlias, $selected';

    final sql = StringBuffer('SELECT $projection FROM ${quoteIdentifier(request.namespace)}');
    if (where.isNotEmpty) sql.write(' WHERE ${where.join(' AND ')}');
    if (sort != null) {
      sql.write(' ORDER BY ${quoteIdentifier(sort)} ${request.descending ? 'DESC' : 'ASC'}');
    }
    // One more than asked for, so "is there another page" is answered by the
    // query rather than by a second COUNT(*) over the whole table.
    sql.write(' LIMIT ${limit + 1} OFFSET $offset');

    final raw = await db.rawQuery(sql.toString(), args);

    final rows = <List<CellValue>>[];
    final handles = <Object?>[];
    var bytes = 0;
    var stoppedForSize = false;

    for (final r in raw.take(limit)) {
      final cells = [
        for (final c in schema.columns) encodeCell(r[c.name], redacted: c.redacted),
      ];
      final size = approximateBytes(cells);
      // Stop before building a frame the socket will refuse. A dropped frame
      // kills the whole stream, not just this query, so overshooting is much
      // worse than returning a short page and saying so.
      if (rows.isNotEmpty && bytes + size > maxPageBytes) {
        stoppedForSize = true;
        break;
      }
      bytes += size;
      rows.add(cells);
      handles.add(schema.rowHandle == null ? null : r[_handleAlias]);
    }

    return CodeScoutPage(
      columns: schema.columns,
      rows: rows,
      handles: handles,
      hasMore: stoppedForSize || raw.length > limit,
      stoppedForSize: stoppedForSize,
    );
  }

  @override
  Future<CodeScoutWriteResult> write(CodeScoutWriteRequest request) async {
    final schema = await describe(request.namespace);
    final handle = schema.rowHandle;
    if (handle == null) {
      return CodeScoutWriteResult.refused(schema.readOnlyBecause!);
    }

    CodeScoutColumn? column;
    for (final c in schema.columns) {
      if (c.name == request.column) column = c;
    }
    if (column == null) {
      return CodeScoutWriteResult.refused('There is no column called "${request.column}".');
    }
    if (column.redacted) {
      return const CodeScoutWriteResult.refused(
          'This column is redacted, so there is nothing to compare against.');
    }

    Object? value;
    try {
      value = coerceForColumn(request.value, column.declaredType);
    } on CoercionError catch (e) {
      return CodeScoutWriteResult.refused(e.message);
    }
    if (value == null && column.notNull) {
      return const CodeScoutWriteResult.refused('This column cannot be empty.');
    }

    // The whole statement, and there is no other. Three identifiers, all of
    // them checked against the schema above, and three bound values.
    //
    // IS rather than = in both comparisons, because = never matches NULL: a
    // row whose value is null would fail the conflict check for ever and a
    // nullable handle could never be addressed at all.
    final sql = 'UPDATE ${quoteIdentifier(request.namespace)} '
        'SET ${quoteIdentifier(column.name)} = ? '
        'WHERE $handle IS ? AND ${quoteIdentifier(column.name)} IS ?';

    final changed = await db.rawUpdate(sql, [value, request.handle, request.was]);
    if (changed > 0) return const CodeScoutWriteResult.written();

    // Nothing matched, which is either of two very different things. Telling
    // them apart costs one query and is the difference between "someone else
    // got there first" and "that row is gone".
    final current = await db.rawQuery(
      'SELECT ${quoteIdentifier(column.name)} FROM ${quoteIdentifier(request.namespace)} '
      'WHERE $handle IS ? LIMIT 1',
      [request.handle],
    );
    if (current.isEmpty) return const CodeScoutWriteResult.rowGone();

    return CodeScoutWriteResult.rowChanged(
      encodeCell(current.first[column.name], redacted: column.redacted).display,
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
