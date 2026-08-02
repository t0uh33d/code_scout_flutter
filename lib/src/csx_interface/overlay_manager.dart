import 'package:code_scout/src/code_scout.dart';
import 'package:code_scout/src/const/global_vars.dart';
import 'package:code_scout/src/csx_interface/menu.dart' show CSxInterface;
import 'package:flutter/material.dart';

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
        onTap: () {
          BuildContext? freshContext = CodeScout.instance.fetcher?.call();
          if (isBottomSheetVisible) {
            isBottomSheetVisible = false;
            if (Navigator.of(freshContext ?? context).canPop()) {
              Navigator.pop(freshContext ?? context, true);
            }
          } else {
            isBottomSheetVisible = true;
            _bottomSheet(freshContext ?? context);
          }
        },
        child: Container(
          color: Colors.red,
          constraints: const BoxConstraints(
            maxHeight: GlobalVars.iconContainerSize,
            maxWidth: GlobalVars.iconContainerSize,
          ),
          child: overlayChild ??
              Image.asset(
                'assets/pim.png',
                package: 'code_scout',
                height: GlobalVars.iconSize,
                width: GlobalVars.iconSize,
                fit: BoxFit.cover,
              ),
        ),
      ),
    );

    insertOverlay(entry);
    return entry;
  }

  Future<dynamic> _bottomSheet(BuildContext context) {
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
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      builder: (context) {
        return const CSxInterface();
      },
    );
  }

  void insertOverlay(OverlayEntry entry) {
    Future.delayed(const Duration(seconds: 0), () {
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
