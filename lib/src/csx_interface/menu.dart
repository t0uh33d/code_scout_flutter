import 'package:code_scout/src/csx_interface/data_tab.dart';
import 'package:code_scout/src/csx_interface/errors_tab.dart';
import 'package:code_scout/src/csx_interface/live_pane.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout/src/csx_interface/logs_tab.dart';
import 'package:code_scout/src/csx_interface/network_tab.dart';
import 'package:code_scout/src/csx_interface/overlay_theme.dart';
import 'package:code_scout/src/csx_interface/overlay_widgets.dart';
import 'package:code_scout/src/db/db_registry.dart';
import 'package:code_scout/src/live/live_session_client.dart';
import 'package:flutter/material.dart';

/// Where the sheet can open.
enum OverlayTab { logs, network, errors, data, info, live }

/// The in-app overlay.
///
/// Three tabs, not five. Logs, Network and Errors are one continuous activity,
/// which is watching what the app has been doing. Data and Info are things you
/// look up occasionally, so they are pushed screens reached from the header
/// rather than sitting permanently next to the screen you read every day.
///
/// It reads [LogBuffer], never the server, so it behaves exactly the same with
/// no server configured. Drop the package into an app, tap the floating button,
/// and the logs are there without standing anything up.
class CSxInterface extends StatefulWidget {
  const CSxInterface({super.key, this.initialTab});

  final OverlayTab? initialTab;

  @override
  State<CSxInterface> createState() => _CSxInterfaceState();
}

class _CSxInterfaceState extends State<CSxInterface> {
  late OverlayTab _tab = widget.initialTab ?? OverlayTab.logs;

  /// What is stacked on top of the tabs. Data, Info and Live are pushed here
  /// rather than being tabs, and a detail screen pushes on top of whatever
  /// opened it.
  final List<Widget> _stack = [];

  @override
  void initState() {
    super.initState();
    if (_tab == OverlayTab.errors) LogBuffer.i.markErrorsSeen();
    final initial = widget.initialTab;
    if (initial == OverlayTab.data || initial == OverlayTab.info || initial == OverlayTab.live) {
      _tab = OverlayTab.logs;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openFor(initial!));
    }
  }

  void _openFor(OverlayTab tab) {
    switch (tab) {
      case OverlayTab.live:
        push(const LivePane());
      case OverlayTab.data:
      case OverlayTab.info:
        // Both land in the next slice. Opening the sheet on Logs is a better
        // answer than a screen that is not there yet.
        break;
      default:
        break;
    }
  }

  void push(Widget screen) => setState(() => _stack.add(screen));

  void pop() => setState(() {
        if (_stack.isNotEmpty) _stack.removeLast();
      });

  void _select(OverlayTab tab) {
    setState(() {
      _tab = tab;
      _stack.clear();
    });
    // Opening the sheet does not clear the unseen count; opening Errors does.
    // A glance at Logs should not silently discard the signal.
    if (tab == OverlayTab.errors) LogBuffer.i.markErrorsSeen();
  }

  @override
  Widget build(BuildContext context) {
    // Material, not a coloured Container: the rows are InkWells, which paint
    // their background and ink on the nearest Material ancestor. A DecoratedBox
    // in between hides both, so every tap looks dead.
    return Material(
      color: CSxColors.background,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: OverlayNavigator(
          push: push,
          pop: pop,
          child: Column(
            children: [
              const _Grip(),
              if (_stack.isEmpty) ...[
                _Header(onSelect: _select),
                _Tabs(active: _tab, onSelect: _select),
                Expanded(child: _body()),
              ] else
                Expanded(child: _stack.last),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() => switch (_tab) {
        OverlayTab.network => const NetworkTab(),
        OverlayTab.errors => const ErrorsTab(),
        _ => const LogsTab(),
      };
}

/// Lets any screen inside the sheet push another without threading callbacks
/// through every widget between here and there.
class OverlayNavigator extends InheritedWidget {
  const OverlayNavigator({
    super.key,
    required this.push,
    required this.pop,
    required super.child,
  });

  final void Function(Widget) push;
  final VoidCallback pop;

  static OverlayNavigator of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OverlayNavigator>()!;

  @override
  bool updateShouldNotify(OverlayNavigator oldWidget) => false;
}

class _Grip extends StatelessWidget {
  const _Grip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 4,
      margin: const EdgeInsets.only(top: 8, bottom: 2),
      decoration: BoxDecoration(
        color: CSxColors.borderStrong,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Identity, live state, the two lookups, and close. Nothing tab-specific:
/// follow and clear live in the tab that owns them.
class _Header extends StatelessWidget {
  const _Header({required this.onSelect});

  final void Function(OverlayTab) onSelect;

  @override
  Widget build(BuildContext context) {
    final nav = OverlayNavigator.of(context);
    // A control that leads to an empty room should not be in the room.
    final hasDatabases = DatabaseRegistry.i.sources.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
      child: Row(
        children: [
          Image.asset('assets/pim.png', package: 'code_scout', height: 24, width: 24),
          const SizedBox(width: 8),
          const _LivePill(),
          const Spacer(),
          if (hasDatabases)
            CSxIconButton(
              icon: Icons.storage_outlined,
              tooltip: 'Data',
              onPressed: () => nav.push(const DataSources()),
            ),
          CSxIconButton(
            icon: Icons.info_outline,
            tooltip: 'Info',
            onPressed: () => nav.push(const _NotYet(title: 'Info')),
          ),
          CSxIconButton(
            icon: Icons.close,
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

/// The connection control, visible from every tab.
///
/// Pairing is a thing you do once, not a place you browse to, so it is not a
/// tab. It is here because a control that reports a connection belongs in the
/// chrome, where it can show state continuously.
class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LiveSessionClient.i,
      builder: (context, _) {
        final state = LiveSessionClient.i.state;
        final (label, colour, dot) = switch (state) {
          LiveSessionState.live => ('Live', CSxColors.primary, true),
          LiveSessionState.connecting => ('Pairing', CSxColors.warning, true),
          _ => ('Go live', CSxColors.muted, false),
        };

        return InkWell(
          onTap: () => OverlayNavigator.of(context).push(const LivePane()),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: dot ? colour.withValues(alpha: 0.12) : Colors.transparent,
              border: Border.all(
                color: dot ? colour.withValues(alpha: 0.5) : CSxColors.borderStrong,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dot) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(label, style: TextStyle(color: colour, fontSize: 11.5)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.active, required this.onSelect});

  final OverlayTab active;
  final void Function(OverlayTab) onSelect;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LogBuffer.i,
      builder: (context, _) {
        final unseen = LogBuffer.i.unseenErrors;
        return Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: CSxColors.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              for (final tab in const [OverlayTab.logs, OverlayTab.network, OverlayTab.errors])
                _TabButton(
                  label: switch (tab) {
                    OverlayTab.logs => 'Logs',
                    OverlayTab.network => 'Network',
                    _ => 'Errors',
                  },
                  // A dot, not a number: the count is already one tap away, and
                  // the floating button is where the number belongs.
                  dot: tab == OverlayTab.errors && unseen > 0,
                  active: tab == active,
                  onTap: () => onSelect(tab),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.active,
    required this.onTap,
    this.dot = false,
  });

  final String label;
  final bool active;
  final bool dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      child: InkWell(
        onTap: onTap,
        child: Container(
          // 44, the platform minimum. The old row was 35.
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? CSxColors.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: active ? CSxColors.white : CSxColors.muted,
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (dot) ...[
                const SizedBox(width: 6),
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(color: CSxColors.error, shape: BoxShape.circle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A pushed screen's header: back, a title, and whatever the screen adds.
class PushedHeader extends StatelessWidget {
  const PushedHeader({super.key, required this.title, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.only(right: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CSxColors.border)),
      ),
      child: Row(
        children: [
          CSxIconButton(
            icon: Icons.chevron_left,
            tooltip: 'Back',
            onPressed: OverlayNavigator.of(context).pop,
          ),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: CSxColors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Stands in for a screen that lands in a later slice, so the control that
/// leads here is honest about it rather than doing nothing.
class _NotYet extends StatelessWidget {
  const _NotYet({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PushedHeader(title: title),
        Expanded(
          child: CSxEmpty(
            title: '$title is next',
            detail: 'This screen is being built. Everything else in the overlay works.',
            mark: true,
          ),
        ),
      ],
    );
  }
}
