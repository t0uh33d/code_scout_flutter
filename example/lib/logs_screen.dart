import 'package:code_scout/code_scout.dart';
import 'package:flutter/material.dart';

import 'main.dart' show hasDashboard;

/// Everything the SDK does that is not network capture: the six levels, the
/// detail you can attach to a log, identity, and pushing a batch by hand.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  String? _user;
  bool _flushing = false;

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scout = CodeScout.instance;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        const _Section(
          'Levels',
          'Six shorthands for the common case. All fire and forget, and none '
              'of them can throw into your code.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip('verbose', () => scout.v('Frame rendered')),
            _Chip('debug', () => scout.d('Cache lookup: hit')),
            _Chip('info', () => scout.i('Checkout started')),
            _Chip('warning', () => scout.w('Retrying in 2s')),
            _Chip('error', () => scout.e('Payment declined')),
            _Chip('fatal', () => scout.f('Unrecoverable state')),
          ],
        ),

        const _Section(
          'Detail',
          'Tags group logs in the dashboard and metadata rides along as JSON. '
              'An error keeps its stack trace, parsed frame by frame.',
        ),
        _Tile(
          'Tags and metadata',
          'One log, two tags, a map of context',
          () {
            scout.i(
              'Checkout completed',
              tags: {'checkout', 'payments'},
              metadata: {'order': 'A-1183', 'total': 42.5, 'currency': 'EUR'},
            );
            _say('Logged with tags and metadata');
          },
        ),
        _Tile(
          'A real error',
          'Thrown and caught, so the stack trace is genuine',
          () {
            try {
              throw StateError('checkout: no payment method on file');
            } catch (e, stackTrace) {
              scout.e('Checkout failed', error: e, stackTrace: stackTrace);
            }
            _say('Logged an error with its stack trace');
          },
        ),
        _Tile(
          'Something worth redacting',
          'The Authorization value never reaches disk',
          () {
            // recommended() covers `authorization` and `password`, so both are
            // replaced with [redacted] at capture — before SQLite, before any
            // upload. Everything else in the map is kept.
            scout.d(
              'Signing in',
              metadata: {
                'authorization': 'Bearer sk_live_dont_log_me',
                'password': 'hunter2',
                'email': 'someone@example.com',
              },
            );
            _say('Logged. The token and password are [redacted]');
          },
        ),

        const _Section(
          'Identity',
          'Opt in, never inferred. Naming someone mid-session attributes the '
              'whole launch, including everything logged before this.',
        ),
        _Tile(
          _user == null ? 'Set a user' : 'Signed in as $_user',
          _user == null
              ? 'setUser("demo-user", traits: {...})'
              : 'Tap to sign out',
          () async {
            if (_user == null) {
              await scout.setUser('demo-user', traits: {'plan': 'free'});
              setState(() => _user = 'demo-user');
            } else {
              await scout.setUser(null);
              setState(() => _user = null);
            }
          },
        ),

        const _Section(
          'Sync and the overlay',
          'Logs are batched and uploaded on a timer. The floating button reads '
              'an in-memory buffer, so it works with no server configured.',
        ),
        _Tile(
          'Upload now',
          hasDashboard
              ? 'flush() — waits for the batch to land or fail'
              : 'No dashboard configured, so this has nothing to send',
          _flushing
              ? null
              : () async {
                  setState(() => _flushing = true);
                  await scout.flush();
                  setState(() => _flushing = false);
                  _say('Flushed');
                },
        ),
        _Tile(
          'Toggle the floating button',
          'Logs, Network, Live and Session, on the device',
          scout.toggleIcon,
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.blurb);

  final String title;
  final String blurb;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            blurb,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      ActionChip(label: Text(label), onPressed: onTap);
}

class _Tile extends StatelessWidget {
  const _Tile(this.title, this.subtitle, this.onTap);

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
        enabled: onTap != null,
      ),
    );
  }
}
