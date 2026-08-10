import 'dart:convert';

import 'package:code_scout/src/const/global_vars.dart';
import 'package:code_scout/src/csx_interface/overlay_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The pieces every overlay screen is built from.
///
/// One file rather than one per widget, because they are small and they only
/// make sense together: the whole point is that a level badge, a filter chip
/// and a key/value row look the same wherever they appear.

/// A tap target that meets the platform minimum without painting 44px of
/// chrome. Padding does the reach.
class CSxIconButton extends StatelessWidget {
  const CSxIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: GlobalVars.minTouchTarget,
        height: GlobalVars.minTouchTarget,
        child: Icon(
          icon,
          size: 19,
          color: onPressed == null
              ? CSxColors.muted
              : active
                  ? CSxColors.primary
                  : CSxColors.muted,
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// The level badge. Colour and the level's name, never colour alone.
class CSxBadge extends StatelessWidget {
  const CSxBadge({super.key, required this.text, required this.colour});

  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: colour,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
          height: 1.2,
        ),
      ),
    );
  }
}

/// How a chip reads, beyond its colour.
enum ChipState {
  /// Neither included nor excluded.
  neutral,

  /// On, for a level toggle.
  on,

  /// Off, for a level toggle. Drawn with a hollow dot rather than by dimming:
  /// half opacity on --muted resolves to 2.41:1 and takes the dot and the
  /// border down with it, so the chip loses its outline too and the one
  /// question the counts exist to answer stops being readable.
  off,

  /// Show only this tag.
  include,

  /// Hide this tag.
  exclude,
}

/// A filter chip.
///
/// Shape carries the state as well as hue, so it survives a colour vision
/// difference: filled dot on, hollow dot off, a leading + for include,
/// strikethrough for exclude.
class CSxChip extends StatelessWidget {
  const CSxChip({
    super.key,
    required this.label,
    required this.state,
    required this.onTap,
    this.count,
    this.dot,
  });

  final String label;
  final ChipState state;
  final VoidCallback onTap;
  final int? count;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final (colour, border, fill) = switch (state) {
      ChipState.include => (
          CSxColors.primary,
          CSxColors.primary.withValues(alpha: 0.5),
          CSxColors.primary.withValues(alpha: 0.12),
        ),
      ChipState.exclude => (
          CSxColors.error,
          CSxColors.error.withValues(alpha: 0.5),
          CSxColors.error.withValues(alpha: 0.10),
        ),
      ChipState.on => (CSxColors.white, CSxColors.borderStrong, CSxColors.card),
      ChipState.off => (CSxColors.muted, CSxColors.border, Colors.transparent),
      ChipState.neutral => (CSxColors.muted, CSxColors.border, Colors.transparent),
    };

    return Semantics(
      button: true,
      selected: state == ChipState.on || state == ChipState.include,
      label: '$label, ${_stateLabel(state)}${count == null ? '' : ', $count'}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 32,
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state == ChipState.include) ...[
                Text('+', style: TextStyle(color: colour, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(width: 5),
              ] else if (dot != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    // Hollow when off, filled when on. The shape is the signal.
                    color: state == ChipState.off ? Colors.transparent : dot,
                    border: state == ChipState.off ? Border.all(color: dot!, width: 1.2) : null,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: colour,
                  fontSize: 11.5,
                  decoration: state == ChipState.exclude ? TextDecoration.lineThrough : null,
                  decorationColor: colour,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text('$count', style: mono.copyWith(color: CSxColors.muted, fontSize: 10.5)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _stateLabel(ChipState s) => switch (s) {
        ChipState.on => 'shown',
        ChipState.off => 'hidden',
        ChipState.include => 'only this',
        ChipState.exclude => 'excluded',
        ChipState.neutral => 'not filtered',
      };
}

/// An uppercase section label, with an optional action on the right.
class CSxSectionHeader extends StatelessWidget {
  const CSxSectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 6, 6),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: CSxColors.muted,
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.9,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// A small bordered button, for Copy next to a section.
class CSxSmallButton extends StatelessWidget {
  const CSxSmallButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        // The visible pill is small; the row it sits in gives it the rest.
        constraints: const BoxConstraints(minHeight: GlobalVars.minTouchTarget - 12),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          border: Border.all(color: CSxColors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: const TextStyle(color: CSxColors.muted, fontSize: 11)),
      ),
    );
  }
}

/// Key/value rows in a bordered card.
class CSxKeyValue extends StatelessWidget {
  const CSxKeyValue({super.key, required this.rows});

  /// Label, value, and an optional colour for the value.
  final List<(String, String, Color?)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: CSxColors.card,
        border: Border.all(color: CSxColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                border: i == rows.length - 1
                    ? null
                    : const Border(bottom: BorderSide(color: CSxColors.border)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      rows[i].$1,
                      style: mono.copyWith(color: CSxColors.muted, fontSize: 11.5),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectableText(
                      rows[i].$2,
                      style: mono.copyWith(
                        color: rows[i].$3 ?? CSxColors.white,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A monospaced block. Wraps rather than scrolling sideways, because a phone
/// has nowhere to scroll sideways to.
class CSxCode extends StatelessWidget {
  const CSxCode({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: CSxColors.background,
        border: Border.all(color: CSxColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        text,
        style: mono.copyWith(color: CSxColors.muted, fontSize: 11, height: 1.55),
      ),
    );
  }
}

/// A note with an information glyph. No coloured left border: a rail on a card
/// is the most recognisable generated-UI tell there is, and a glyph carries the
/// same meaning.
class CSxHint extends StatelessWidget {
  const CSxHint({super.key, required this.child, this.tone});

  final Widget child;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: CSxColors.card,
        border: Border.all(color: CSxColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            tone == null ? Icons.info_outline : Icons.error_outline,
            size: 15,
            color: tone ?? CSxColors.muted,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: DefaultTextStyle(
              style: const TextStyle(color: CSxColors.muted, fontSize: 11.5, height: 1.5),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// An empty state. Always says what to do next, never just what is absent.
class CSxEmpty extends StatelessWidget {
  const CSxEmpty({
    super.key,
    required this.title,
    required this.detail,
    this.action,
    this.mark = false,
  });

  final String title;
  final String detail;
  final Widget? action;

  /// Draw Pim above the title. For the states worth being warm about.
  final bool mark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mark)
            Opacity(
              opacity: 0.5,
              child: Image.asset('assets/pim.png', package: 'code_scout', height: 56, width: 56),
            ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: CSxColors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(color: CSxColors.muted, fontSize: 12, height: 1.5),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// A full-width button that meets the touch minimum.
class CSxButton extends StatelessWidget {
  const CSxButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: expand ? double.infinity : null,
        constraints: const BoxConstraints(minHeight: GlobalVars.minTouchTarget),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          // An explicit disabled fill rather than opacity: opacity put the
          // label at 2.99:1, and it is the label you read while typing the
          // characters that will enable it.
          color: disabled
              ? CSxColors.card
              : primary
                  // primaryDeep, not primary: white on #078DEE is 3.47:1.
                  ? CSxColors.primaryDeep
                  : CSxColors.card,
          border: Border.all(
            color: disabled
                ? CSxColors.border
                : primary
                    ? CSxColors.primaryDeep
                    : CSxColors.borderStrong,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: disabled
                ? CSxColors.muted
                : primary
                    ? Colors.white
                    : CSxColors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// A horizontally scrolling row of chips, with a fade at the trailing edge.
///
/// Without the fade, a chip sliced by the screen edge reads as a layout bug
/// rather than as something you swipe.
class CSxChipRow extends StatelessWidget {
  const CSxChipRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: GlobalVars.minTouchTarget,
      child: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Colors.black, Colors.black, Colors.transparent],
          stops: [0, 0.92, 1],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: children.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, i) => children[i],
        ),
      ),
    );
  }
}

/// Copies [text] and says so. Every copy in the overlay goes through here, so
/// the confirmation is the same everywhere.
Future<void> copyAndTell(BuildContext context, String text, String what) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  await Clipboard.setData(ClipboardData(text: text));
  messenger?.showSnackBar(SnackBar(content: Text('$what copied')));
}

/// Rows when every value is a scalar, indented JSON otherwise.
///
/// Two renderers, one rule, no tree widget and no third mode to learn. The
/// alternative is what shipped: `metadata.toString()`, a Dart map on one
/// unwrapped line, which is not JSON and pastes into nothing.
bool isFlatMap(Map<String, dynamic> map) =>
    map.values.every((v) => v == null || v is num || v is bool || v is String);

String prettyJson(Object? value) {
  try {
    return JsonEncoder.withIndent('  ', (o) => o.toString()).convert(value);
  } catch (_) {
    return value.toString();
  }
}
