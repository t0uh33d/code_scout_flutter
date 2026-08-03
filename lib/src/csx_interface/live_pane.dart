import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/overlay_theme.dart';
import 'package:code_scout/src/live/live_session_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The overlay's Live tab — the prototype's one missing overlay screen.
///
/// Somebody on the dashboard presses New session, reads a six-character code
/// off the screen, and calls it out to whoever is holding the phone. This is
/// where they type it.
class LivePane extends StatefulWidget {
  const LivePane({super.key});

  @override
  State<LivePane> createState() => _LivePaneState();
}

class _LivePaneState extends State<LivePane> {
  final TextEditingController _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final code = _code.text.trim();
    if (code.isEmpty || _busy) return;

    setState(() => _busy = true);
    await CodeScout.instance.startLiveSession(code);
    if (!mounted) return;
    setState(() => _busy = false);

    if (LiveSessionClient.i.isLive) _code.clear();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds off the client itself, so the panel follows the connection
    // rather than the two drifting apart.
    return AnimatedBuilder(
      animation: LiveSessionClient.i,
      builder: (context, _) {
        final client = LiveSessionClient.i;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            switch (client.state) {
              LiveSessionState.live => _connected(client),
              LiveSessionState.connecting => _connecting(),
              _ => _pairing(client),
            },
          ],
        );
      },
    );
  }

  Widget _pairing(LiveSessionClient client) {
    final configured = CodeScout.instance.configuration.projectCredentials != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Start live session',
          style: TextStyle(
            color: CSxColors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'On the dashboard, open Live devices and press New session. '
          'Type the code it shows you here.',
          style: TextStyle(color: CSxColors.muted, fontSize: 12, height: 1.45),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _code,
          enabled: configured && !_busy,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          inputFormatters: pairingCodeFormatters(),
          onSubmitted: (_) => _connect(),
          style: const TextStyle(
            color: CSxColors.white,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: 8,
            fontFamily: 'monospace',
          ),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            counterText: '',
            hintText: '••••••',
            hintStyle: const TextStyle(
              color: CSxColors.faint,
              fontSize: 24,
              letterSpacing: 8,
            ),
            filled: true,
            fillColor: CSxColors.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        if (client.error != null) ...[
          const SizedBox(height: 10),
          Text(
            client.error!,
            style: const TextStyle(color: CSxColors.error, fontSize: 12, height: 1.4),
          ),
        ],
        if (!configured) ...[
          const SizedBox(height: 10),
          const Text(
            'No server is configured, so there is nothing to stream to. '
            'Everything else in this overlay still works.',
            style: TextStyle(color: CSxColors.muted, fontSize: 12, height: 1.45),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: configured && !_busy ? _connect : null,
          style: FilledButton.styleFrom(
            backgroundColor: CSxColors.primary,
            disabledBackgroundColor: CSxColors.card,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            _busy ? 'Connecting…' : 'Connect',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _connecting() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: CSxColors.primary),
          ),
          SizedBox(height: 14),
          Text('Connecting…', style: TextStyle(color: CSxColors.muted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _connected(LiveSessionClient client) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: CSxColors.debug,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Live',
              style: TextStyle(
                color: CSxColors.debug,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Everything this app logs is arriving on the dashboard as it happens. '
          'Nothing is stored there unless somebody turns on Persist.',
          style: TextStyle(color: CSxColors.muted, fontSize: 12, height: 1.45),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => CodeScout.instance.stopLiveSession(),
          style: FilledButton.styleFrom(
            backgroundColor: CSxColors.card,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text(
            'Stop streaming',
            style: TextStyle(color: CSxColors.error, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// The characters a pairing code can contain.
///
/// It has to match the server's alphabet in `internal/domain/live.go`. If the
/// two ever drift, the field silently eats the character the person is trying
/// to type and the code never completes — so this is a named constant with a
/// test rather than a regex buried in a widget.
const pairingAlphabet = '234679ACDEFGHJKMNPQRTUVWXYZ';

/// Upper-cases, then drops anything outside the alphabet. Filtering while they
/// type beats refusing a finished code and making them work out which
/// character was wrong.
List<TextInputFormatter> pairingCodeFormatters() => [
      UpperCaseFormatter(),
      FilteringTextInputFormatter.allow(RegExp('[$pairingAlphabet]')),
    ];

/// Upper-cases as they type. A code is read aloud and typed one-handed, and
/// the phone's keyboard will happily offer lower case regardless of
/// [TextCapitalization].
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue next) {
    return next.copyWith(text: next.text.toUpperCase());
  }
}
