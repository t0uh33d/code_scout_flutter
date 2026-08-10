import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout/src/csx_interface/overlay_theme.dart';
import 'package:code_scout/src/live/live_session_client.dart';
import 'package:flutter/material.dart';

/// The floating button.
///
/// It is the only Code Scout pixel on screen while somebody is using the app,
/// so it carries state rather than being a logo. Two signals, both earned:
/// a count of errors you have not looked at, and whether a dashboard is
/// watching this device right now.
class OverlayButton extends StatelessWidget {
  const OverlayButton({super.key, this.child, required this.size});

  /// Replaces Pim, for an app that wants its own mark.
  final Widget? child;

  final double size;

  @override
  Widget build(BuildContext context) {
    // Both notifiers, because the button reflects both. Listenable.merge keeps
    // it to one rebuild when they fire together.
    return AnimatedBuilder(
      animation: Listenable.merge([LogBuffer.i, LiveSessionClient.i]),
      builder: (context, _) {
        final errors = LogBuffer.i.unseenErrors;
        final live = LiveSessionClient.i.isLive;

        return SizedBox(
          // Room for the badge and the ring to sit outside the chip without
          // being clipped by the Positioned box.
          width: size + 12,
          height: size + 12,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (live)
                Semantics(
                  label: 'Live session running',
                  child: Container(
                    width: size + 10,
                    height: size + 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: CSxColors.primary, width: 2),
                    ),
                  ),
                ),
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  // From the palette, not the raw red the previous version
                  // painted straight onto a Container.
                  color: CSxColors.elevated,
                  shape: BoxShape.circle,
                  border: Border.all(color: CSxColors.borderStrong),
                  boxShadow: const [
                    BoxShadow(color: Color(0x8C000000), blurRadius: 22, offset: Offset(0, 8)),
                  ],
                ),
                alignment: Alignment.center,
                child: child ??
                    Image.asset(
                      'assets/pim.png',
                      package: 'code_scout',
                      height: size * 0.58,
                      width: size * 0.58,
                      fit: BoxFit.contain,
                    ),
              ),
              if (errors > 0)
                Positioned(
                  top: 0,
                  right: 0,
                  child: _Badge(count: errors),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    // Past three digits the badge stops being a number and becomes a shape, and
    // the difference between 400 and 900 errors is not a difference anyone acts
    // on differently.
    final label = count > 99 ? '99+' : '$count';

    return Semantics(
      label: '$count unseen ${count == 1 ? 'error' : 'errors'}',
      child: Container(
        constraints: const BoxConstraints(minWidth: 19),
        height: 19,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          // Not CSxColors.error: white on #F85149 is 3.35:1, and this is a
          // 10px bold numeral, which cannot reach AA through the large-text
          // rule. #DA3633 puts it at 4.61:1.
          color: CSxColors.errorDeep,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black, width: 2),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: mono.copyWith(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            height: 1,
          ),
        ),
      ),
    );
  }
}
