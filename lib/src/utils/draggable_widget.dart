import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The floating button's position and drag behaviour.
///
/// Free positioning is deliberate and unchanged: nothing snaps to an edge and
/// nothing moves the button for you. What is enforced is that it cannot end up
/// somewhere you cannot reach it.
class DraggableFloatingWindow extends StatefulWidget {
  const DraggableFloatingWindow({
    super.key,
    required this.child,
    required this.size,
    required this.onTap,
    this.onLongPress,
  });

  final Widget child;

  /// The button's own size. The clamp needs the whole of it, not half.
  final double size;

  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<DraggableFloatingWindow> createState() => _DraggableFloatingWindowState();
}

class _DraggableFloatingWindowState extends State<DraggableFloatingWindow> {
  /// The button's top-left, in global coordinates.
  Offset? _position;

  /// Where inside the button the finger landed. Kept for the length of the
  /// drag so the button moves with the finger instead of jumping to sit under
  /// it: the previous version recentred on pan start, so a tap that drifted two
  /// pixels teleported the button across the screen.
  Offset _grab = Offset.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery.sizeOf and paddingOf register a dependency, so this runs on
    // rotation, on a keyboard opening, and on a window resize. Re-clamping here
    // is the whole fix for a button that was stored once and never recomputed:
    // rotating to landscape used to leave it off the screen with no way back.
    final current = _position;
    _position = current == null ? _defaultPosition() : _clamp(current);
  }

  /// The gap kept between the button and the edge of the usable area, so it
  /// never sits flush against a rounded corner or a gesture bar.
  static const double _margin = 8;

  /// Bottom right, inside the safe area. Not the top left, which is where the
  /// back button and the system navigation live.
  Offset _defaultPosition() {
    final screen = MediaQuery.sizeOf(context);
    return _clamp(Offset(screen.width, screen.height - widget.size - 24));
  }

  Offset _clamp(Offset raw) {
    final screen = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);

    final minX = safe.left + _margin;
    final minY = safe.top + _margin;
    // The whole button, not half of it. Clamping against half was why 26px of
    // it could hang off any edge.
    final maxX = screen.width - safe.right - _margin - widget.size;
    final maxY = screen.height - safe.bottom - _margin - widget.size;

    // On a viewport too small to hold the button and its margins, max lands
    // below min and clamp throws. Pinning to the top left is the only position
    // left, and it beats an exception in a debug overlay.
    return Offset(
      raw.dx.clamp(minX, math.max(minX, maxX)),
      raw.dy.clamp(minY, math.max(minY, maxY)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final position = _position ??= _defaultPosition();

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onPanStart: (details) {
          _grab = details.globalPosition - position;
        },
        onPanUpdate: (details) {
          setState(() => _position = _clamp(details.globalPosition - _grab));
        },
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: widget.child,
      ),
    );
  }
}
