import 'package:code_scout/src/csx_interface/overlay_theme.dart';
import 'package:flutter/material.dart';

/// The search field, plus whatever controls belong beside it.
///
/// A stateful wrapper around the controller so a parent can hold the query as a
/// plain String without owning a TextEditingController's lifecycle, and so the
/// clear button is part of the field rather than something every caller draws.
class CSxSearchField extends StatefulWidget {
  const CSxSearchField({
    super.key,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.actions = const [],
  });

  final String hint;
  final String value;
  final ValueChanged<String> onChanged;
  final List<Widget> actions;

  @override
  State<CSxSearchField> createState() => _CSxSearchFieldState();
}

class _CSxSearchFieldState extends State<CSxSearchField> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(CSxSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A parent that clears the query, rather than the user typing, has to reach
    // the field. Guarded so it does not fight the cursor while typing.
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 38),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: CSxColors.background,
                border: Border.all(color: CSxColors.borderStrong),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 15, color: CSxColors.muted),
                  const SizedBox(width: 7),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onChanged: widget.onChanged,
                      style: const TextStyle(color: CSxColors.white, fontSize: 12),
                      cursorColor: CSxColors.primary,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: widget.hint,
                        // --muted, not --faint: a hint is text.
                        hintStyle: const TextStyle(color: CSxColors.muted, fontSize: 12),
                      ),
                    ),
                  ),
                  if (widget.value.isNotEmpty)
                    InkWell(
                      onTap: () {
                        _controller.clear();
                        widget.onChanged('');
                      },
                      // A 14px glyph in a 32px target. The visible cross stays
                      // small; the tappable box does not.
                      child: const SizedBox(
                        width: 32,
                        height: 32,
                        child: Icon(Icons.close, size: 15, color: CSxColors.muted),
                      ),
                    ),
                ],
              ),
            ),
          ),
          ...widget.actions,
        ],
      ),
    );
  }
}
