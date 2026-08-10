import 'package:code_scout/src/code_scout.dart';
import 'package:code_scout/src/const/global_vars.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout/src/csx_interface/log_clipboard.dart';
import 'package:code_scout/src/csx_interface/menu.dart' show CSxInterface, OverlayTab;
import 'package:code_scout/src/csx_interface/overlay_button.dart';
import 'package:code_scout/src/csx_interface/overlay_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/draggable_widget.dart';

class OverlayManager {
  static final OverlayManager _singleton = OverlayManager._internal();

  factory OverlayManager() {
    return _singleton;
  }

  OverlayManager._internal();

  final _entries = <OverlayEntry>[];
  bool isBottomSheetVisible = false;
  BuildContext? context;
  Widget? overlayChild;

  static OverlayState? of(BuildContext context) {
    return Overlay.of(context);
  }

  OverlayEntry createOverlayEntry() {
    final entry = OverlayEntry(
      builder: (context) => DraggableFloatingWindow(
        size: GlobalVars.buttonSize,
        onTap: () => _toggleSheet(context),
        onLongPress: () => _quickActions(context),
        child: OverlayButton(
          size: GlobalVars.buttonSize,
          child: overlayChild,
        ),
      ),
    );

    insertOverlay(entry);
    return entry;
  }

  void _toggleSheet(BuildContext context, {OverlayTab? tab}) {
    final BuildContext? freshContext = CodeScout.instance.fetcher?.call();
    final target = freshContext ?? context;

    if (isBottomSheetVisible) {
      isBottomSheetVisible = false;
      if (Navigator.of(target).canPop()) {
        Navigator.pop(target, true);
      }
      if (tab == null) return;
    }

    isBottomSheetVisible = true;
    _bottomSheet(target, tab: tab);
  }

  /// The four things worth doing without opening anything.
  ///
  /// Copy last error earns its place: the most common thing anyone does with
  /// this overlay is paste an error into a chat window, and today that costs
  /// four taps and a long press on the right row.
  Future<void> _quickActions(BuildContext context) async {
    final BuildContext? freshContext = CodeScout.instance.fetcher?.call();
    final target = freshContext ?? context;
    if (!target.mounted) return;

    final groups = LogBuffer.i.errorGroups();
    final messenger = ScaffoldMessenger.maybeOf(target);

    final choice = await showModalBottomSheet<String>(
      context: target,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _QuickActions(hasError: groups.isNotEmpty),
    );

    switch (choice) {
      case 'copy':
        if (groups.isEmpty) return;
        await Clipboard.setData(ClipboardData(
          text: formatLogForClipboard(
            groups.first.latest,
            session: CodeScout.instance.currentSession,
            sessionId: CodeScout.instance.currentSessionId,
          ),
        ));
        messenger?.showSnackBar(const SnackBar(content: Text('Error copied')));
      case 'live':
        if (!target.mounted) return;
        _toggleSheet(target, tab: OverlayTab.live);
      case 'clear':
        LogBuffer.i.clear();
        messenger?.showSnackBar(const SnackBar(content: Text('Cleared this launch')));
      case 'hide':
        CodeScout.instance.hideIcon();
    }
  }

  Future<dynamic> _bottomSheet(BuildContext context, {OverlayTab? tab}) {
    return showModalBottomSheet(
      context: context,
      // The sheet is a log viewer, not a menu: without isScrollControlled it is
      // capped at half the screen and its list gets a few rows to work with.
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      showDragHandle: false,
      // Tapping the dimmed app behind it closes the sheet, which is what every
      // other sheet on the platform does.
      isDismissible: true,
      // Tight, not a maximum. With only a maximum the sheet takes the height of
      // whichever tab is open, so it grew and shrank on every switch. One size
      // for all of them is what makes the tab row stay where you last tapped it.
      constraints: BoxConstraints.tightFor(
        height: MediaQuery.of(context).size.height * 0.85,
      ),
      builder: (context) {
        return CSxInterface(initialTab: tab);
      },
    ).whenComplete(() => isBottomSheetVisible = false);
  }

  void insertOverlay(OverlayEntry entry) {
    Future.delayed(const Duration(seconds: 0), () {
      // No context means there is no widget tree to hang the button on:
      // freshContextFetcher is optional, so an app that calls init() before it
      // has one lands here, and so does anything headless. Everything else in
      // the SDK works without an overlay, and this runs a turn later in the
      // event loop where a throw is nobody's to catch.
      if (context == null) return;

      if (_entries.isEmpty) {
        _entries.add(entry);
      }
      Overlay.of(context!).insert(entry);
    });
  }

  // Remove an existing overlay
  void removeOverlay() {
    if (_entries.isNotEmpty) {
      final lastEntry = _entries.removeLast();
      lastEntry.remove();
    }
    return;
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.hasError});

  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: CSxColors.elevated,
          border: Border.all(color: CSxColors.borderStrong),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Action(
              label: 'Copy last error',
              value: 'copy',
              // Nothing to copy is a reason to disable, not to hide: a menu
              // whose items move between openings is a menu you have to read.
              enabled: hasError,
            ),
            _Action(label: 'Start a live session', value: 'live'),
            _Action(label: 'Clear this launch', value: 'clear'),
            _Action(label: 'Hide until restart', value: 'hide', muted: true, last: true),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.value,
    this.enabled = true,
    this.muted = false,
    this.last = false,
  });

  final String label;
  final String value;
  final bool enabled;
  final bool muted;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => Navigator.pop(context, value) : null,
      child: Container(
        width: double.infinity,
        // 44 is the platform minimum for anything you tap.
        constraints: const BoxConstraints(minHeight: 48),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: CSxColors.border)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: !enabled || muted ? CSxColors.muted : CSxColors.white,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
