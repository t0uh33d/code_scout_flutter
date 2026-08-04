import 'package:flutter/material.dart';

import 'demo_stores.dart';

/// Everything this app stores locally, and buttons that change it.
///
/// The pairing to try: open the Database tab on the dashboard, press one of
/// these, then press Refresh there. What you wrote on the phone is in the grid.
/// Then edit a value in the grid and press Reload here — and notice it does not
/// come back on its own, because the app read these rows into memory when the
/// screen was built. That is true of every app, and it is why the dashboard
/// warns you after a write.
class DataScreen extends StatefulWidget {
  const DataScreen({super.key, required this.stores});

  final DemoStores? stores;

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  List<Map<String, Object?>> _flags = const [];
  List<Map<String, Object?>> _cart = const [];
  Map<String, String> _prefs = const {};
  Map<String, String> _notes = const {};
  DateTime? _readAt;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(DataScreen old) {
    super.didUpdateWidget(old);
    if (old.stores != widget.stores) _reload();
  }

  Future<void> _reload() async {
    final s = widget.stores;
    if (s == null) return;
    final flags = await s.flags();
    final cart = await s.cart();
    if (!mounted) return;
    setState(() {
      _flags = flags;
      _cart = cart;
      _prefs = {for (final k in s.prefs.getKeys()) k: '${s.prefs.get(k)}'};
      _notes = {for (final k in s.notes.keys) '$k': s.notes.get(k) ?? ''};
      _readAt = DateTime.now();
    });
  }

  Future<void> _write(Future<void> Function() action) async {
    await action();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stores;
    if (s == null) {
      // Either still opening, or this platform has no plugin for one of them.
      // The second is what happens under `flutter test`, and the app carrying
      // on regardless is the point.
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Local storage is not available here. It is either still opening, or '
            'this platform has no implementation for it — check the Logs tab.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Intro(readAt: _readAt, onReload: _reload),
        const SizedBox(height: 20),
        _Section(
          title: 'example_app.db',
          subtitle: 'SQLite through CodeScoutSqflite',
          actions: [
            _Action('Add a cart item', () => _write(s.addCartItem)),
            _Action('Toggle checkout_v2', () => _write(() => s.toggleFlag('checkout_v2'))),
          ],
          children: [
            for (final f in _flags)
              _Row('${f['key']}',
                  '${(f['enabled'] as int? ?? 0) != 0 ? 'on' : 'off'}  ·  ${f['rollout_pct']}%'),
            const Divider(height: 20),
            for (final item in _cart)
              _Row('${item['title']}', 'qty ${item['qty']}  ·  ${item['price_cents']}p'),
          ],
        ),
        _Section(
          title: 'prefs',
          subtitle: 'shared_preferences through CodeScoutKeyValue',
          actions: [
            _Action('Bump launch_count', () => _write(s.bumpLaunchCount)),
            _Action('Touch locale', () => _write(s.touchPrefs)),
          ],
          children: [
            if (_prefs.isEmpty) const _Row('nothing yet', 'press a button above'),
            for (final e in _prefs.entries) _Row(e.key, e.value),
          ],
        ),
        _Section(
          title: 'hive · notes',
          subtitle: 'a Hive box through the same CodeScoutKeyValue',
          actions: [_Action('Add a note', () => _write(s.addNote))],
          children: [
            if (_notes.isEmpty) const _Row('no notes', 'press Add a note'),
            for (final e in _notes.entries) _Row(e.key, e.value),
          ],
        ),
      ],
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.readAt, required this.onReload});

  final DateTime? readAt;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Three stores, browsable from the dashboard',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            const Text(
              'Start a live session on the dashboard, type the code into the floating '
              'button, and open the Database tab. Press anything below, then Refresh '
              'there — what you wrote is in the grid.',
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.tonal(onPressed: onReload, child: const Text('Reload from disk')),
                const SizedBox(width: 12),
                if (readAt != null)
                  Text('read at ${readAt!.toLocal().toString().substring(11, 19)}', style: small),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Nothing here updates on its own. Edit a value in the dashboard and it '
              'will not appear until you press Reload, because the app is holding '
              'these rows in memory. Every app is.',
              style: small,
            ),
          ],
        ),
      ),
    );
  }
}

class _Action {
  const _Action(this.label, this.onPressed);
  final String label;
  final VoidCallback onPressed;
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<_Action> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final a in actions)
                OutlinedButton(onPressed: a.onPressed, child: Text(a.label)),
            ],
          ),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.name, this.detail);
  final String name;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.zero,
      title: Text(name, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
      subtitle: Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }
}
