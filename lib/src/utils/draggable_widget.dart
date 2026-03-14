import 'package:code_scout/src/const/global_vars.dart';
import 'package:flutter/material.dart';

class DraggableFloatingWindow extends StatefulWidget {
  const DraggableFloatingWindow(
      {super.key, required this.child, required this.onTap});
  final Widget child;
  final void Function() onTap;
  @override
  State<DraggableFloatingWindow> createState() =>
      _DraggableFloatingWindowState();
}

class _DraggableFloatingWindowState extends State<DraggableFloatingWindow> {
  Offset? position;

  Offset _clampPosition(Offset raw) {
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    return Offset(
      raw.dx.clamp(0, screen.width - GlobalVars.iconContainerSize / 2),
      raw.dy.clamp(padding.top,
          screen.height - padding.bottom - GlobalVars.iconContainerSize / 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position?.dx ?? 0,
      top: position?.dy ?? 100,
      child: GestureDetector(
        onPanStart: (details) => setState(() => position = _clampPosition(
            details.globalPosition -
                const Offset(
                    GlobalVars.iconHalfSize, GlobalVars.iconHalfSize))),
        onPanUpdate: (details) => setState(() {
          position = _clampPosition(details.globalPosition -
              const Offset(GlobalVars.iconHalfSize, GlobalVars.iconHalfSize));
        }),
        onTap: widget.onTap,
        child: widget.child,
      ),
    );
  }
}
