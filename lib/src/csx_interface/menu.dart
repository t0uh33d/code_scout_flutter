import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout/src/csx_interface/overlay_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The in-app overlay, following the prototype's s-overlay: a sheet over the
/// host app with Logs, Network and Session.
///
/// It reads [LogBuffer], never the server, so it behaves exactly the same with
/// no server configured — which is the point of local mode. Drop the package
/// into an app, tap the floating button, and the logs are there without
/// standing anything up.
///
/// The prototype's third panel, the pairing code that starts a live session,
/// waits on the streaming server. It is left out rather than drawn as a screen
/// whose Connect button goes nowhere.
class CSxInterface extends StatefulWidget {
  const CSxInterface({super.key});

  @override
  State<CSxInterface> createState() => _CSxInterfaceState();
}

enum _Tab { logs, network, session }

class _CSxInterfaceState extends State<CSxInterface> {
  _Tab _tab = _Tab.logs;

  /// Tri-state per tag, the same cycle as the dashboard's chips: neutral →
  /// only this → hide this → neutral.
  final Set<String> _included = {};
  final Set<String> _excluded = {};

  /// Levels below this are hidden. The prototype's note asks for the level and
  /// tag filters the dashboard has.
  LogLevel _minimum = LogLevel.all;

  void _cycleTag(String tag) {
    setState(() {
      if (_included.remove(tag)) {
        _excluded.add(tag);
      } else if (!_excluded.remove(tag)) {
        _included.add(tag);
      }
    });
  }

  bool _matches(LogEntry entry) {
    if (entry.level.value < _minimum.value) return false;

    final tags = entry.tags ?? const <String>{};
    if (_excluded.isNotEmpty && tags.any(_excluded.contains)) return false;
    // Included tags are an OR, which is what a row of chips reads like: tap
    // two and you expect both, not only the logs carrying both at once.
    if (_included.isNotEmpty && !tags.any(_included.contains)) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LogBuffer.i,
      builder: (context, _) {
        final entries = LogBuffer.i.entries;
        // Material, not a coloured Container: the rows are ListTiles, which
        // paint their background and ink on the nearest Material ancestor. A
        // DecoratedBox in between hides both, so every tap looks dead.
        return Material(
          color: CSxColors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Grip(),
                _Header(count: entries.length),
                _Tabs(active: _tab, onSelect: (t) => setState(() => _tab = t)),
                Flexible(child: _body(entries)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _body(List<LogEntry> entries) {
    switch (_tab) {
      case _Tab.logs:
        final visible = entries.where(_matches).toList();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LevelRow(minimum: _minimum, onSelect: (l) => setState(() => _minimum = l)),
            _TagRow(
              tags: LogBuffer.i.tags(),
              included: _included,
              excluded: _excluded,
              onTap: _cycleTag,
            ),
            Flexible(
              child: visible.isEmpty
                  ? const _Empty(
                      title: 'Nothing to show',
                      detail: 'Logs from this launch appear here as they happen.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: visible.length,
                      itemBuilder: (context, i) => _LogRow(entry: visible[i]),
                    ),
            ),
          ],
        );
      case _Tab.network:
        final calls = LogBuffer.i.calls();
        return calls.isEmpty
            ? const _Empty(
                title: 'No network calls',
                detail: 'Add the Dio interceptor or the HTTP client wrapper and calls show up here.',
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: calls.length,
                itemBuilder: (context, i) => _CallRow(call: calls[i]),
              );
      case _Tab.session:
        return _SessionPane(logs: entries.length);
    }
  }
}

class _Grip extends StatelessWidget {
  const _Grip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: CSxColors.border,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 10, 12),
      child: Row(
        children: [
          const Text(
            'Code Scout',
            style: TextStyle(color: CSxColors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(width: 8),
          Text(
            count >= LogBuffer.maxEntries ? 'last $count' : '$count',
            style: const TextStyle(color: CSxColors.faint, fontSize: 11),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close, color: CSxColors.muted, size: 20),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.active, required this.onSelect});

  final _Tab active;
  final ValueChanged<_Tab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CSxColors.border)),
      ),
      child: Row(
        children: [
          for (final tab in _Tab.values)
            _TabButton(
              label: switch (tab) {
                _Tab.logs => 'Logs',
                _Tab.network => 'Network',
                _Tab.session => 'Session',
              },
              active: tab == active,
              onTap: () => onSelect(tab),
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? CSxColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? CSxColors.white : CSxColors.muted,
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _LevelRow extends StatelessWidget {
  const _LevelRow({required this.minimum, required this.onSelect});

  final LogLevel minimum;
  final ValueChanged<LogLevel> onSelect;

  // "all" first, then the levels worth filtering to. `off` is a threshold that
  // would hide everything, so it is not offered.
  static const _levels = [
    LogLevel.all,
    LogLevel.debug,
    LogLevel.info,
    LogLevel.warning,
    LogLevel.error,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final level in _levels)
            _Chip(
              label: level == LogLevel.all ? 'All' : level.name,
              active: level == minimum,
              dot: level == LogLevel.all ? null : levelColor(level.name),
              onTap: () => onSelect(level),
            ),
        ],
      ),
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.tags,
    required this.included,
    required this.excluded,
    required this.onTap,
  });

  final List<String> tags;
  final Set<String> included;
  final Set<String> excluded;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final tag in tags)
            _Chip(
              label: tag,
              active: included.contains(tag),
              struck: excluded.contains(tag),
              onTap: () => onTap(tag),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
    this.struck = false,
    this.dot,
  });

  final String label;
  final bool active;
  final bool struck;
  final Color? dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colour = struck
        ? CSxColors.error
        : active
            ? CSxColors.primary
            : CSxColors.muted;
    final lit = active || struck;

    return Padding(
      padding: const EdgeInsets.only(right: 6, top: 6, bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: lit ? colour.withValues(alpha: 0.12) : Colors.transparent,
            border: Border.all(color: lit ? colour.withValues(alpha: 0.5) : CSxColors.border),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: colour,
                  fontSize: 11,
                  decoration: struck ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A log row expands to whatever it carries — the error, the stack trace, the
/// metadata. Collapsed it is one line, because the list is read by scanning.
class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final colour = levelColor(entry.level.name);
    final details = _details();

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        // Not every log has more to show, and a chevron that opens onto
        // nothing is worse than no chevron.
        trailing: details.isEmpty ? const SizedBox.shrink() : null,
        title: Row(
          children: [
            _Badge(text: entry.level.name, colour: colour),
            const SizedBox(width: 8),
            Text(
              _time(entry.timestamp),
              style: mono.copyWith(color: CSxColors.faint, fontSize: 10),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            entry.message,
            style: TextStyle(
              color: entry.level.value >= LogLevel.error.value ? CSxColors.error : CSxColors.white,
              fontSize: 12.5,
            ),
          ),
        ),
        children: [
          for (final section in details) _Section(title: section.$1, body: section.$2),
        ],
      ),
    );
  }

  List<(String, String)> _details() {
    final out = <(String, String)>[];
    if (entry.error != null) out.add(('Error', entry.error.toString()));
    final trace = entry.formattedStackTrace;
    if (trace != null && trace.isNotEmpty) out.add(('Stack trace', trace.join('\n')));
    if (entry.metadata != null && entry.metadata!.isNotEmpty) {
      out.add(('Metadata', entry.metadata.toString()));
    }
    if (entry.tags != null && entry.tags!.isNotEmpty) {
      out.add(('Tags', entry.tags!.join(', ')));
    }
    return out;
  }
}

class _CallRow extends StatelessWidget {
  const _CallRow({required this.call});

  final OverlayCall call;

  @override
  Widget build(BuildContext context) {
    final colour = call.failed
        ? CSxColors.error
        : call.status == 'pending'
            ? CSxColors.warning
            : CSxColors.debug;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: Row(
          children: [
            Text(
              call.method,
              style: mono.copyWith(color: colour, fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            _Badge(text: call.status, colour: colour),
            const Spacer(),
            Text(
              _duration(call.duration),
              style: mono.copyWith(color: CSxColors.faint, fontSize: 10),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            call.path,
            style: mono.copyWith(color: CSxColors.white, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        children: [
          for (final phase in NetworkCallPhase.values)
            if (call.phase(phase) != null)
              _Section(
                title: phase.name,
                body: call.phase(phase)!.metadata?.toString() ?? '—',
              ),
        ],
      ),
    );
  }
}

/// What this launch is, which is the first thing anyone reporting a bug gets
/// asked for. Long-press to copy, because reading a UUID off a screen out loud
/// is how bug reports end up attached to the wrong session.
class _SessionPane extends StatelessWidget {
  const _SessionPane({required this.logs});

  final int logs;

  @override
  Widget build(BuildContext context) {
    final session = CodeScout.instance.currentSession;

    final rows = <(String, String?)>[
      ('Session', CodeScout.instance.currentSessionId),
      ('Installation', session?.installationId),
      ('User', session?.userId ?? 'anonymous'),
      ('Device', _deviceLabel(session)),
      ('App', _appLabel(session)),
      ('Started', _time(session?.startedAt)),
      ('Logs held', '$logs'),
      (
        'Sync',
        CodeScout.instance.configuration.projectCredentials == null
            ? 'local only — no server configured'
            : 'uploading to the server'
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        for (final row in rows) _Fact(label: row.$1, value: row.$2 ?? '—'),
      ],
    );
  }

  static String _deviceLabel(SessionRecord? s) {
    if (s == null) return '—';
    final model = s.deviceModel ?? 'Unknown device';
    final os = [s.osName, s.osVersion].where((p) => p != null && p.isNotEmpty).join(' ');
    return os.isEmpty ? model : '$model · $os';
  }

  static String _appLabel(SessionRecord? s) {
    if (s == null || (s.appVersion == null && s.buildNumber == null)) return '—';
    final version = s.appVersion ?? '';
    final build = s.buildNumber;
    return build == null ? version : '$version+$build';
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: CSxColors.faint,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 3),
          GestureDetector(
            onLongPress: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (context.mounted) {
                ScaffoldMessenger.maybeOf(context)
                    ?.showSnackBar(SnackBar(content: Text('$label copied')));
              }
            },
            child: Text(value, style: mono.copyWith(color: CSxColors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.colour});

  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: colour,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: CSxColors.faint,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: CSxColors.card,
            border: Border.all(color: CSxColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            body,
            style: mono.copyWith(color: CSxColors.muted, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(color: CSxColors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(color: CSxColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

String _time(DateTime? at) {
  if (at == null) return '—';
  final local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

String _duration(Duration? d) {
  if (d == null) return '—';
  if (d.inMilliseconds < 1000) return '${d.inMilliseconds}ms';
  return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
}
