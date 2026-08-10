import 'package:code_scout/src/csx_interface/menu.dart';
import 'package:code_scout/src/csx_interface/overlay_theme.dart';
import 'package:code_scout/src/csx_interface/overlay_widgets.dart';
import 'package:code_scout/src/csx_interface/search_field.dart';
import 'package:code_scout/src/db/db_registry.dart';
import 'package:code_scout/src/db/db_source.dart';
import 'package:code_scout/src/db/db_value.dart';
import 'package:flutter/material.dart';

/// Browsing the app's own local storage, on the device.
///
/// **Read only, always.** The overlay never calls [CodeScoutSource.write], and
/// that is the whole guarantee: read-only here is a rule this file keeps, not
/// something the types enforce, because `write` is reachable by any caller.
/// Editing runs through the dashboard, which carries the old value to detect a
/// conflict, needs project-manage rights, and gives you the whole cell and a
/// real keyboard. A phone gives you none of the three.
///
/// It needs no live session and no server: [DatabaseRegistry] is local and the
/// sources answer locally, so this works in local mode like everything else in
/// the overlay.
class DataSources extends StatelessWidget {
  const DataSources({super.key});

  @override
  Widget build(BuildContext context) {
    final sources = DatabaseRegistry.i.sources;

    return Column(
      children: [
        const PushedHeader(title: 'Data'),
        Expanded(
          child: sources.isEmpty
              ? const _NothingRegistered()
              : ListView.builder(
                  itemCount: sources.length,
                  itemBuilder: (context, i) => _SourceRow(entry: sources[i]),
                ),
        ),
        if (sources.isNotEmpty)
          const _Footnote(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: 'Read only on this device. '),
              TextSpan(
                text: 'Editing runs through the dashboard',
                style: TextStyle(color: CSxColors.white, fontWeight: FontWeight.w600),
              ),
              TextSpan(text: ' during a live session.'),
            ])),
          ),
      ],
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.entry});

  final RegisteredSource entry;

  @override
  Widget build(BuildContext context) {
    final isKeyValue = entry.source.kind == CodeScoutSourceKind.keyValue;
    return _Row(
      icon: isKeyValue ? Icons.list_alt_outlined : Icons.storage_outlined,
      title: entry.name,
      // No row or table counts anywhere: the four ops are namespaces, describe,
      // read and write, and a page reports hasMore rather than a total. Saying
      // "8 tables" would mean counting them, and saying "1,284 rows" would mean
      // an op that does not exist.
      subtitle: isKeyValue ? 'Key-value' : 'SQLite',
      // Writable is what the dashboard may change. It says nothing about here.
      tag: entry.writable ? 'writable' : null,
      onTap: () => OverlayNavigator.of(context).push(DataNamespaces(entry: entry)),
    );
  }
}

/// The tables or boxes inside one source.
class DataNamespaces extends StatefulWidget {
  const DataNamespaces({super.key, required this.entry});

  final RegisteredSource entry;

  @override
  State<DataNamespaces> createState() => _DataNamespacesState();
}

class _DataNamespacesState extends State<DataNamespaces> {
  late final Future<List<CodeScoutNamespace>> _namespaces = widget.entry.source.namespaces();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PushedHeader(title: widget.entry.name),
        _Crumbs(parts: ['Data', widget.entry.name]),
        Expanded(
          child: FutureBuilder<List<CodeScoutNamespace>>(
            future: _namespaces,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const _Loading(label: 'Reading the schema');
              }
              if (snapshot.hasError) {
                // One source failing must not empty the screen, and it has to
                // say which one and why.
                return _Failed(name: widget.entry.name, error: snapshot.error!);
              }
              final namespaces = snapshot.data ?? const [];
              if (namespaces.isEmpty) {
                return const CSxEmpty(
                  title: 'Nothing in here',
                  detail: 'This source reports no tables.',
                );
              }
              return ListView.builder(
                itemCount: namespaces.length,
                itemBuilder: (context, i) => _Row(
                  icon: Icons.table_rows_outlined,
                  title: namespaces[i].name,
                  subtitle: namespaces[i].kind.name,
                  onTap: () => OverlayNavigator.of(context).push(DataRows(
                    entry: widget.entry,
                    namespace: namespaces[i].name,
                  )),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One namespace's rows, with a filter that runs in SQL.
class DataRows extends StatefulWidget {
  const DataRows({super.key, required this.entry, required this.namespace});

  final RegisteredSource entry;
  final String namespace;

  @override
  State<DataRows> createState() => _DataRowsState();
}

class _DataRowsState extends State<DataRows> {
  CodeScoutSchema? _schema;
  CodeScoutPage? _page;
  Object? _error;
  bool _loading = true;

  String _query = '';
  String? _filterColumn;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final schema = _schema ?? await widget.entry.source.describe(widget.namespace);
      final column = _filterColumn ?? schema.columns.firstOrNull?.name;
      final page = await widget.entry.source.read(CodeScoutReadRequest(
        namespace: widget.namespace,
        // The filter runs in SQL, over the whole namespace, not over the rows
        // already loaded. CodeScoutReadRequest has carried filters, sortColumn
        // and paging all along; sqflite_source turns them into an escaped LIKE
        // against a column checked for membership.
        filters: _query.isEmpty || column == null ? const {} : {column: _query},
      ));
      if (!mounted) return;
      setState(() {
        _schema = schema;
        _filterColumn = column;
        _page = page;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final schema = _schema;
    final page = _page;

    return Column(
      children: [
        PushedHeader(title: widget.namespace),
        _Crumbs(parts: ['Data', widget.entry.name, widget.namespace]),
        if (schema != null && schema.columns.isNotEmpty) ...[
          CSxSearchField(
            hint: 'Filter ${_filterColumn ?? ''}'.trim(),
            value: _query,
            onChanged: (q) {
              _query = q;
              _load();
            },
          ),
          CSxChipRow(
            children: [
              for (final column in schema.columns)
                CSxChip(
                  label: column.name,
                  state: column.name == _filterColumn ? ChipState.on : ChipState.neutral,
                  onTap: () {
                    _filterColumn = column.name;
                    _load();
                  },
                ),
            ],
          ),
          const Divider(height: 1, color: CSxColors.border),
        ],
        Expanded(child: _body(schema, page)),
        if (page != null && !_loading)
          _Footnote(
            child: Text(
              // What is actually known. There is no count op, so a total would
              // be a number nothing measured.
              page.hasMore
                  ? 'Showing the first ${page.rows.length}, and there are more.'
                  : '${page.rows.length} ${page.rows.length == 1 ? 'row' : 'rows'}.',
            ),
          ),
      ],
    );
  }

  Widget _body(CodeScoutSchema? schema, CodeScoutPage? page) {
    if (_error != null) return _Failed(name: widget.namespace, error: _error!);
    if (_loading && page == null) return const _Loading(label: 'Reading rows');
    if (schema == null || page == null) return const SizedBox.shrink();

    if (page.rows.isEmpty) {
      return CSxEmpty(
        title: _query.isEmpty ? 'No rows' : 'Nothing matches',
        detail: _query.isEmpty
            ? 'This table is empty.'
            : 'No row has "$_query" in $_filterColumn.',
        action: _query.isEmpty
            ? null
            : CSxButton(
                label: 'Clear filter',
                onPressed: () {
                  _query = '';
                  _load();
                },
              ),
      );
    }

    return ListView.builder(
      itemCount: page.rows.length,
      itemBuilder: (context, i) => _DataRow(
        page: page,
        index: i,
        namespace: widget.namespace,
        source: widget.entry.name,
      ),
    );
  }
}

/// One row in the list: a label and the next few cells.
class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.page,
    required this.index,
    required this.namespace,
    required this.source,
  });

  final CodeScoutPage page;
  final int index;
  final String namespace;
  final String source;

  @override
  Widget build(BuildContext context) {
    final cells = page.rows[index];
    final (label, rest) = labelAndRest(page, index);

    return _Row(
      title: label,
      subtitle: rest.isEmpty ? null : rest.join('  ·  '),
      onTap: () => OverlayNavigator.of(context).push(DataRowDetail(
        page: page,
        cells: cells,
        label: label,
        namespace: namespace,
        source: source,
      )),
    );
  }
}

/// The row's label and the cells shown underneath it.
///
/// The label is the row handle when there is one, which is the rowid for an
/// ordinary SQLite table and the key for a key-value store, and the first
/// column otherwise. The subtitle is the next three non-null cells in schema
/// order, whatever their type. A rule with an unwritten exception is a guess
/// wearing a rule's clothes, so there is no special case for text columns and
/// no reformatting.
(String, List<String>) labelAndRest(CodeScoutPage page, int index) {
  final cells = page.rows[index];
  final handle = index < page.handles.length ? page.handles[index] : null;

  var skip = -1;
  String label;
  if (handle != null) {
    label = '$handle';
    // The handle is usually also a column; do not print it twice.
    skip = page.columns.indexWhere((c) => c.name == page.rowHandle);
  } else if (cells.isNotEmpty) {
    label = _show(cells.first);
    skip = 0;
  } else {
    label = '—';
  }

  final rest = <String>[];
  for (var i = 0; i < cells.length && rest.length < 3; i++) {
    if (i == skip) continue;
    final cell = cells[i];
    if (cell.display == null) continue;
    rest.add(_show(cell));
  }
  return (label, rest);
}

String _show(CellValue cell) {
  // A blob, a truncated string or a redacted value. The source already says why
  // in words meant for a person, so use them: "<blob, 41 KB>" beats a bare
  // null, and shows the size without pretending to show the value.
  if (!cell.editable && cell.display == null) {
    return '<${cell.because ?? 'not shown'}>';
  }
  final value = cell.display;
  if (value == null) return 'null';
  if (value is String) return value;
  return '$value';
}

/// One row, opened.
class DataRowDetail extends StatelessWidget {
  const DataRowDetail({
    super.key,
    required this.page,
    required this.cells,
    required this.label,
    required this.namespace,
    required this.source,
  });

  final CodeScoutPage page;
  final List<CellValue> cells;
  final String label;
  final String namespace;
  final String source;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PushedHeader(
          title: '$namespace · $label',
          actions: [
            CSxIconButton(
              icon: Icons.copy_all_outlined,
              tooltip: 'Copy row',
              onPressed: () => copyAndTell(context, _asText(), 'Row'),
            ),
          ],
        ),
        _Crumbs(parts: ['…', source, namespace, label]),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              const CSxSectionHeader(title: 'Row'),
              CSxKeyValue(
                rows: [
                  for (var i = 0; i < cells.length && i < page.columns.length; i++)
                    (page.columns[i].name, _show(cells[i]), _colourOf(cells[i])),
                ],
              ),
            ],
          ),
        ),
        // Said once, exactly where you would have reached to change something,
        // and nowhere else. Values are never tap targets, so nobody taps a dead
        // cell and concludes the feature is broken.
        _Footnote(
          child: Text.rich(TextSpan(children: [
            const TextSpan(text: 'Editing needs the dashboard. '),
            TextSpan(
              text: 'Start a live session ›',
              style: const TextStyle(color: CSxColors.primary, fontWeight: FontWeight.w600),
            ),
          ])),
          onTap: () => OverlayNavigator.of(context).push(const _LiveFromData()),
        ),
      ],
    );
  }

  Color? _colourOf(CellValue cell) {
    if (!cell.editable) return CSxColors.warning;
    if (cell.display == null) return CSxColors.muted;
    if (cell.display is num) return CSxColors.info;
    if (cell.display is String) return CSxColors.debug;
    return null;
  }

  String _asText() {
    final out = StringBuffer()..writeln('$source · $namespace · $label');
    for (var i = 0; i < cells.length && i < page.columns.length; i++) {
      out.writeln('${page.columns[i].name}: ${_show(cells[i])}');
    }
    return out.toString().trimRight();
  }
}

/// Pairing, reached from the place you wanted to edit.
class _LiveFromData extends StatelessWidget {
  const _LiveFromData();

  @override
  Widget build(BuildContext context) => const _PairingProxy();
}

/// Kept separate so data_tab does not import live_pane's whole tree just to
/// name it in one callback.
class _PairingProxy extends StatelessWidget {
  const _PairingProxy();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const PushedHeader(title: 'Live session'),
        Expanded(
          child: CSxEmpty(
            title: 'Pair from the header',
            detail: 'Tap Go live at the top of the sheet to enter the code from your dashboard.',
            action: CSxButton(
              label: 'Back',
              onPressed: OverlayNavigator.of(context).pop,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    this.subtitle,
    this.icon,
    this.tag,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: CSxColors.border)),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: CSxColors.muted),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono.copyWith(
                      color: CSxColors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: CSxColors.muted, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            if (tag != null) ...[
              const SizedBox(width: 8),
              CSxBadge(text: tag!, colour: CSxColors.warning),
            ],
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 16, color: CSxColors.muted),
          ],
        ),
      ),
    );
  }
}

/// Where you are, four levels into a browser inside a bottom sheet.
class _Crumbs extends StatelessWidget {
  const _Crumbs({required this.parts});

  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < parts.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5),
                  child: Text('›', style: TextStyle(color: CSxColors.muted, fontSize: 11)),
                ),
              Text(
                parts[i],
                style: mono.copyWith(
                  // --muted, not --faint: the ancestor segments are the
                  // navigational half of the breadcrumb, and --faint is 1.8:1.
                  color: i == parts.length - 1 ? CSxColors.white : CSxColors.muted,
                  fontSize: 11,
                  fontWeight: i == parts.length - 1 ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: CSxColors.muted),
          ),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(color: CSxColors.muted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.name, required this.error});

  final String name;
  final Object error;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        CSxHint(
          tone: CSxColors.error,
          child: Text.rich(TextSpan(children: [
            TextSpan(
              text: 'Could not open $name. ',
              style: const TextStyle(color: CSxColors.white, fontWeight: FontWeight.w600),
            ),
            TextSpan(text: '$error'),
          ])),
        ),
        const CSxHint(
          child: Text(
            'It is still registered, so it will appear again once whatever is holding it lets go.',
          ),
        ),
      ],
    );
  }
}

class _NothingRegistered extends StatelessWidget {
  const _NothingRegistered();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const CSxEmpty(
          mark: true,
          title: 'No databases registered',
          detail: 'Nothing is browsable until the app names it. '
              'Register the connection you already have.',
        ),
        const CSxSectionHeader(title: 'SQLite'),
        const CSxCode(text: "CodeScout.instance.registerDatabase(\n"
            "  'shop.db', CodeScoutSqflite(db),\n"
            "  writable: kDebugMode,\n"
            ");"),
        const CSxHint(
          child: Text.rich(TextSpan(children: [
            TextSpan(
              text: 'writable',
              style: TextStyle(color: CSxColors.white, fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: ' only affects the dashboard. The overlay never edits, whatever it is set to.',
            ),
          ])),
        ),
      ],
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: CSxColors.border)),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: CSxColors.muted, fontSize: 11.5, height: 1.5),
          child: child,
        ),
      ),
    );
  }
}
