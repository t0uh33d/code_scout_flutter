import 'dart:io';

import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/data_tab.dart';
import 'package:code_scout/src/csx_interface/menu.dart';
import 'package:code_scout/src/db/db_value.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A source that records every call, so a test can assert what the overlay
/// asked for and, more importantly, what it never asked for.
class _SpySource implements CodeScoutSource {
  _SpySource({this.rows = const [], this.failNamespaces = false});

  final List<List<CellValue>> rows;
  final bool failNamespaces;

  final List<CodeScoutReadRequest> reads = [];
  int writes = 0;

  @override
  CodeScoutSourceKind get kind => CodeScoutSourceKind.sql;

  @override
  Future<List<CodeScoutNamespace>> namespaces() async {
    if (failNamespaces) throw StateError('database is locked');
    return const [CodeScoutNamespace(name: 'orders', kind: CodeScoutNamespaceKind.table)];
  }

  @override
  Future<CodeScoutSchema> describe(String namespace) async => const CodeScoutSchema(
        namespace: 'orders',
        columns: [
          CodeScoutColumn(name: 'id', declaredType: 'INTEGER', primaryKey: true),
          CodeScoutColumn(name: 'status', declaredType: 'TEXT'),
          CodeScoutColumn(name: 'amount', declaredType: 'INTEGER'),
        ],
        rowHandle: 'rowid',
      );

  @override
  Future<CodeScoutPage> read(CodeScoutReadRequest request) async {
    reads.add(request);
    return CodeScoutPage(
      columns: const [
        CodeScoutColumn(name: 'id', declaredType: 'INTEGER', primaryKey: true),
        CodeScoutColumn(name: 'status', declaredType: 'TEXT'),
        CodeScoutColumn(name: 'amount', declaredType: 'INTEGER'),
      ],
      rows: rows,
      handles: List<Object?>.generate(rows.length, (i) => 4812 - i),
      hasMore: false,
      rowHandle: 'rowid',
    );
  }

  @override
  Future<CodeScoutWriteResult> write(CodeScoutWriteRequest request) async {
    writes++;
    return const CodeScoutWriteResult.written();
  }
}

void main() {
  late _SpySource spy;

  setUp(() {
    DatabaseRegistry.i.clear();
    spy = _SpySource(rows: [
      [
        const CellValue(4812),
        const CellValue('declined'),
        const CellValue(8950),
      ],
      [
        const CellValue(4811),
        const CellValue('paid'),
        const CellValue(2400),
      ],
    ]);
  });
  tearDown(DatabaseRegistry.i.clear);

  // A real stack, not a no-op: half these screens are only reachable by
  // pushing, and a harness that swallows the push tests nothing past the first
  // list.
  Future<void> pump(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: _Host(root: screen)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('nothing is browsable until the app names it', (tester) async {
    await pump(tester, const DataSources());

    expect(find.text('No databases registered'), findsOneWidget);
    expect(find.textContaining('registerDatabase'), findsOneWidget,
        reason: 'an empty state has to say what to do next');
  });

  testWidgets('a registered source is listed, with no invented counts', (tester) async {
    DatabaseRegistry.i.register('shop.db', spy);
    await pump(tester, const DataSources());

    expect(find.text('shop.db'), findsOneWidget);
    // There is no count op: namespaces, describe, read and write are the whole
    // vocabulary, and a page reports hasMore rather than a total. "8 tables"
    // would be a number nothing measured.
    expect(find.textContaining('tables'), findsNothing);
    expect(find.text('SQLite'), findsOneWidget);
  });

  testWidgets('writable is about the dashboard, and says so', (tester) async {
    DatabaseRegistry.i.register('shop.db', spy, writable: true);
    await pump(tester, const DataSources());

    expect(find.text('WRITABLE'), findsOneWidget);
    expect(find.textContaining('Editing runs through the dashboard'), findsOneWidget);
  });

  testWidgets('a source that will not open fails alone, named, with the reason',
      (tester) async {
    final broken = _SpySource(failNamespaces: true);
    DatabaseRegistry.i.register('analytics.db', broken);

    await pump(tester, DataNamespaces(entry: DatabaseRegistry.i.sources.first));

    expect(find.textContaining('Could not open analytics.db'), findsOneWidget);
    expect(find.textContaining('database is locked'), findsOneWidget);
    expect(find.textContaining('still registered'), findsOneWidget);
  });

  testWidgets('the filter runs in SQL, over the namespace, not over loaded rows',
      (tester) async {
    DatabaseRegistry.i.register('shop.db', spy);
    await pump(tester, DataRows(entry: DatabaseRegistry.i.sources.first, namespace: 'orders'));

    expect(spy.reads.length, 1);
    expect(spy.reads.first.filters, isEmpty);

    await tester.enterText(find.byType(TextField).first, 'declined');
    await tester.pumpAndSettle();

    // A second read went to the source carrying the filter. Filtering the rows
    // already on screen would have issued no read at all.
    expect(spy.reads.length, greaterThan(1));
    expect(spy.reads.last.filters, {'id': 'declined'},
        reason: 'the filter names the selected column and travels to the source');
  });

  testWidgets('picking a column changes which column is filtered', (tester) async {
    DatabaseRegistry.i.register('shop.db', spy);
    await pump(tester, DataRows(entry: DatabaseRegistry.i.sources.first, namespace: 'orders'));

    await tester.tap(find.text('status'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'paid');
    await tester.pumpAndSettle();

    expect(spy.reads.last.filters, {'status': 'paid'});
  });

  testWidgets('a row is labelled by its handle, then the next cells', (tester) async {
    DatabaseRegistry.i.register('shop.db', spy);
    await pump(tester, DataRows(entry: DatabaseRegistry.i.sources.first, namespace: 'orders'));

    // The handle is the label.
    expect(find.text('4812'), findsOneWidget);
    // And the cells after it, in schema order, whatever their type. The amount
    // is an INTEGER column and still appears: the rule is not "text columns".
    expect(find.textContaining('declined'), findsOneWidget);
    expect(find.textContaining('8950'), findsOneWidget);
  });

  testWidgets('an empty result tells a filter apart from an empty table', (tester) async {
    DatabaseRegistry.i.register('shop.db', _SpySource(rows: const []));
    await pump(tester, DataRows(entry: DatabaseRegistry.i.sources.first, namespace: 'orders'));

    expect(find.text('No rows'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Nothing matches'), findsOneWidget);
    expect(find.text('No rows'), findsNothing);
  });

  // The guarantee the whole screen rests on, asserted against the source
  // rather than through the UI.
  //
  // A sweep that taps every control kept missing places: it tapped only Text
  // widgets at first, then popped out of the pushed screen before reaching the
  // header. Each time the sabotage passed, which meant the test was claiming
  // coverage it did not have. Read-only here is a rule this code keeps, so the
  // honest way to check it is to read the code: there is no path through a UI
  // sweep that reaches an affordance nobody wired up yet, but there is no
  // hiding a call from a grep.
  test('no overlay screen calls write', () {
    final dir = Directory('lib/src/csx_interface');
    final offenders = <String>[];

    for (final file in dir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      // Strip comments so prose about writing does not trip it.
      final code = source
          .replaceAll(RegExp(r'^\s*///.*$', multiLine: true), '')
          .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');
      // CodeScoutWriteRequest is the tight signal: CodeScoutSource.write takes
      // one and nothing else, so a write cannot be issued without naming the
      // type. A bare `.write(` would be too broad — StringBuffer has one, and
      // the clipboard formatter uses it.
      if (code.contains('CodeScoutWriteRequest') ||
          RegExp(r'\bsource\.write\s*\(').hasMatch(code)) {
        offenders.add(file.path);
      }
    }

    expect(offenders, isEmpty,
        reason: 'the overlay must never issue the update op; editing runs '
            'through the dashboard, which carries the old value to detect a '
            'conflict and needs project-manage rights');
  });

  // And the ordinary path, so a write reachable by browsing is caught as
  // behaviour rather than only as text.
  testWidgets('browsing never writes, whatever it is registered as', (tester) async {
    DatabaseRegistry.i.register('shop.db', spy, writable: true);
    await pump(tester, DataRows(entry: DatabaseRegistry.i.sources.first, namespace: 'orders'));

    await tester.enterText(find.byType(TextField).first, 'dec');
    await tester.pumpAndSettle();
    await tester.tap(find.text('4812').first);
    await tester.pumpAndSettle();

    expect(spy.writes, 0);
  });

  testWidgets('a value nobody was shown is marked, not printed', (tester) async {
    DatabaseRegistry.i.register(
      'shop.db',
      _SpySource(rows: [
        [
          const CellValue(4812),
          const CellValue(null, editable: false, because: 'blob, 41 KB'),
          const CellValue(8950),
        ],
      ]),
    );
    await pump(tester, DataRows(entry: DatabaseRegistry.i.sources.first, namespace: 'orders'));

    await tester.tap(find.text('4812').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('<blob, 41 KB>'), findsOneWidget,
        reason: 'the size is shown without pretending to show the value');
  });
}


/// Holds a stack the way the sheet does, so push actually navigates.
class _Host extends StatefulWidget {
  const _Host({required this.root});

  final Widget root;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final List<Widget> _stack = [];

  @override
  Widget build(BuildContext context) {
    return OverlayNavigator(
      push: (w) => setState(() => _stack.add(w)),
      pop: () => setState(() {
        if (_stack.isNotEmpty) _stack.removeLast();
      }),
      child: _stack.isEmpty ? widget.root : _stack.last,
    );
  }
}
