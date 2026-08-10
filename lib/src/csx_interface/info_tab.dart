import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout/src/csx_interface/menu.dart';
import 'package:code_scout/src/csx_interface/overlay_theme.dart';
import 'package:code_scout/src/csx_interface/overlay_widgets.dart';
import 'package:code_scout/src/log/log_persistence_service.dart';
import 'package:code_scout/src/log/log_sync_worker.dart';
import 'package:flutter/material.dart';

/// One question at two moments.
///
/// A developer wiring the SDK up for the first time asks *is this reaching my
/// dashboard*. QA holding a broken build asks *is this being recorded, and what
/// do I send the developer*. Both are the state of one connection and the facts
/// about one launch, so they are one screen.
///
/// It leads with the answer rather than the data behind it: the Session tab it
/// replaces opened with seven facts in the order they were coded, and neither
/// person's question was among them.
class InfoScreen extends StatefulWidget {
  const InfoScreen({super.key});

  @override
  State<InfoScreen> createState() => _InfoScreenState();
}

class _InfoScreenState extends State<InfoScreen> {
  bool _testing = false;
  int _pending = -1;

  @override
  void initState() {
    super.initState();
    _countPending();
  }

  /// Read from SQLite, not from the buffer above it. The buffer is what the
  /// Logs tab draws and it never drains, so showing its size next to the word
  /// upload read as a queue that was going nowhere.
  Future<void> _countPending() async {
    try {
      final n = await LogPersistenceService.i.pendingCount();
      if (mounted) setState(() => _pending = n);
    } catch (_) {
      // A database that will not open must not take the screen down with it.
      if (mounted) setState(() => _pending = -1);
    }
  }

  Future<void> _test() async {
    final creds = CodeScout.instance.configuration.projectCredentials;
    if (creds == null) return;
    setState(() => _testing = true);
    await creds.check();
    if (!mounted) return;
    setState(() => _testing = false);
  }

  Future<void> _uploadNow() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    // Clears the pause first. Plain flush() returns immediately while a backoff
    // is running, so a button that only called it would be a guaranteed no-op
    // on the one screen that exists to explain the pause.
    LogSyncWorker.i.clearBackoff();
    await CodeScout.instance.flush();
    await _countPending();
    messenger?.showSnackBar(const SnackBar(content: Text('Upload attempted')));
  }

  @override
  Widget build(BuildContext context) {
    final config = CodeScout.instance.configuration;
    final creds = config.projectCredentials;
    final session = CodeScout.instance.currentSession;
    final waiting = LogSyncWorker.i.backoffRemaining;

    return Column(
      children: [
        PushedHeader(
          title: 'Info',
          actions: [
            CSxIconButton(
              icon: Icons.copy_all_outlined,
              tooltip: 'Copy all',
              onPressed: () => copyAndTell(context, _report(), 'Report'),
            ),
            CSxIconButton(
              icon: Icons.close,
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 20),
            children: [
              _verdict(creds, waiting),
              if (creds != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: CSxButton(
                          label: _testing ? 'Testing…' : 'Test connection',
                          onPressed: _testing ? null : _test,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CSxButton(
                          label: waiting == null ? 'Upload now' : 'Try now, do not wait',
                          onPressed: _uploadNow,
                        ),
                      ),
                    ],
                  ),
                ),
              ..._checks(creds),
              ..._connection(creds),
              ..._wiredUp(),
              ..._capture(config),
              ..._upload(creds, waiting),
              ..._launch(session),
            ],
          ),
        ),
      ],
    );
  }

  // -- the answer, before any of the data behind it -------------------------

  Widget _verdict(ProjectCredentials? creds, Duration? waiting) {
    if (creds == null) {
      // Local mode is a supported way to use this, not a failure, so it gets a
      // neutral colour and a next step rather than a red cross.
      return const _Verdict(
        tone: _Tone.warn,
        title: 'Local only',
        detail: 'No credentials configured. Logs stay on this device.',
      );
    }
    if (_testing) {
      return const _Verdict(
        tone: _Tone.busy,
        title: 'Testing the connection',
        detail: 'Asking the server.',
      );
    }

    switch (creds.outcome) {
      case ConnectionOutcome.ok:
        if (!CodeScout.instance.isSessionSampledIn) {
          return const _Verdict(
            tone: _Tone.warn,
            title: 'Connected, recording nothing',
            detail: 'This launch was not sampled.',
          );
        }
        if (waiting != null) {
          return _Verdict(
            tone: _Tone.warn,
            title: 'Paused after repeated failures',
            detail: 'Retrying in ${_short(waiting)}.',
          );
        }
        return _Verdict(
          tone: _Tone.ok,
          title: 'Connected',
          strong: creds.projectName,
          detail: _pending <= 0 ? 'Nothing waiting to upload.' : '$_pending waiting to upload.',
        );
      case ConnectionOutcome.unreachable:
        return _Verdict(
          tone: _Tone.bad,
          title: 'Cannot reach the server',
          detail: '${creds.detail ?? 'No answer'} · ${creds.link}',
        );
      case ConnectionOutcome.rejected:
        return const _Verdict(
          tone: _Tone.bad,
          title: 'Credentials were turned down',
          detail: 'The server answered, but not with a yes.',
        );
      case ConnectionOutcome.notFound:
        return const _Verdict(
          tone: _Tone.bad,
          title: 'No Code Scout at that address',
          detail: 'Something answered, but it is not a dashboard.',
        );
      case ConnectionOutcome.refused:
        return _Verdict(
          tone: _Tone.bad,
          title: 'The server refused',
          detail: creds.detail ?? '',
        );
      case ConnectionOutcome.unchecked:
      case ConnectionOutcome.unconfigured:
        return const _Verdict(
          tone: _Tone.busy,
          title: 'Not checked yet',
          detail: 'Tap Test connection.',
        );
    }
  }

  /// The four checks, in order, each waiting on the one above. A step that has
  /// not run says so rather than showing a cross it has not earned.
  List<Widget> _checks(ProjectCredentials? creds) {
    if (creds == null) {
      return [
        const CSxHint(
          child: Text(
            'This is a working setup, not a broken one. Everything in this overlay works with '
            'no server at all. Add credentials when you want a dashboard.',
          ),
        ),
        const CSxSectionHeader(title: 'Add them like this'),
        const CSxCode(text: 'CodeScoutConfiguration(\n'
            '  projectCredentials: ProjectCredentials(\n'
            "    link: 'https://you.example/',\n"
            "    projectID: '...',\n"
            "    projectSecret: '...',\n"
            '  ),\n'
            ')'),
      ];
    }
    if (creds.outcome == ConnectionOutcome.unchecked && !_testing) return [];

    final reached = creds.outcome != ConnectionOutcome.unreachable;
    final accepted = creds.outcome.isOk;

    return [
      const CSxSectionHeader(title: 'What was checked'),
      _Steps(steps: [
        (_StepState.ok, 'Credentials are configured', null),
        if (_testing && !reached)
          (_StepState.busy, 'Server answered', null)
        else
          (
            reached ? _StepState.ok : _StepState.bad,
            'Server answered',
            reached ? null : creds.detail
          ),
        (
          !reached
              ? _StepState.skipped
              : accepted || creds.outcome == ConnectionOutcome.notFound
                  ? _StepState.ok
                  : _StepState.bad,
          'Credentials accepted',
          null
        ),
        (
          accepted ? _StepState.ok : _StepState.skipped,
          'Project identified',
          creds.projectName,
        ),
      ]),
      // The two mistakes that account for most first runs, named rather than
      // left for a search engine.
      if (creds.outcome == ConnectionOutcome.unreachable) ...[
        if (creds.link.contains('localhost') || creds.link.contains('127.0.0.1'))
          const CSxHint(
            child: Text.rich(TextSpan(children: [
              TextSpan(
                text: 'On a physical device, localhost is the phone. ',
                style: TextStyle(color: CSxColors.white, fontWeight: FontWeight.w600),
              ),
              TextSpan(
                text: 'Point the link at your machine on the network, something like '
                    'http://192.168.1.24:24275/, and check the dashboard is running.',
              ),
            ])),
          ),
        if (creds.link.startsWith('http://'))
          const CSxHint(
            child: Text.rich(TextSpan(children: [
              TextSpan(
                text: 'Android blocks plain HTTP by default. ',
                style: TextStyle(color: CSxColors.white, fontWeight: FontWeight.w600),
              ),
              TextSpan(
                text: 'Use https, or allow cleartext for this host in your network security '
                    'config while you are developing.',
              ),
            ])),
          ),
      ],
    ];
  }

  List<Widget> _connection(ProjectCredentials? creds) {
    if (creds == null) return [];
    return [
      const CSxSectionHeader(title: 'Connection'),
      CSxKeyValue(rows: [
        ('server', Uri.tryParse(creds.link)?.host ?? creds.link, null),
        ('project', creds.projectName ?? 'not known yet', creds.projectName == null ? CSxColors.muted : null),
        ('id', _short8(creds.projectID), null),
        // Never the secret itself, not even the last few characters. Test
        // connection answers "did I paste the right one" better than eyeballing
        // it, and this screen gets screenshotted into bug reports.
        ('secret', 'set · ${creds.projectSecret.length} characters', CSxColors.muted),
      ]),
    ];
  }

  /// Which companion packages are loaded.
  List<Widget> _wiredUp() {
    final loaded = NetworkManager.i.integrations;
    final databases = DatabaseRegistry.i.sources;

    return [
      const CSxSectionHeader(title: 'Network interception'),
      // All three register when they are constructed, so absent really does
      // mean not installed rather than not used yet.
      _Steps(steps: [
        for (final (key, label) in const [
          ('dio', 'Dio interceptor'),
          ('http', 'HTTP client wrapper'),
          ('talker', 'Talker observer'),
        ])
          (
            loaded.contains(key) ? _StepState.ok : _StepState.skipped,
            label,
            loaded.contains(key) ? null : 'not installed',
          ),
      ]),
      if (loaded.isEmpty) ...[
        const CSxHint(
          child: Text.rich(TextSpan(children: [
            TextSpan(
              text: 'The Network tab will stay empty. ',
              style: TextStyle(color: CSxColors.white, fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: 'Network calls are captured by a companion package, not by the core. '
                  'Add whichever one your app uses.',
            ),
          ])),
        ),
        const CSxSectionHeader(title: 'For dio'),
        const CSxCode(text: 'dio.interceptors.add(\n  CodeScoutDioInterceptor(),\n);'),
      ],
      const CSxSectionHeader(title: 'Local storage'),
      if (databases.isEmpty)
        const _Steps(steps: [(_StepState.skipped, 'No databases registered', null)])
      else
        _Steps(steps: [
          for (final db in databases)
            (_StepState.ok, db.name, db.writable ? 'writable' : 'read only'),
        ]),
    ];
  }

  /// The three silent reasons a dashboard stays empty while everything reports
  /// healthy: level, sampling, redaction. None of them was visible on device.
  List<Widget> _capture(CodeScoutConfiguration config) {
    final logging = config.logging;
    final redaction = config.redaction;
    final local = logging.sessionSampleRate;
    final remote = config.projectCredentials?.serverSampleRate;
    final kept = CodeScout.instance.isSessionSampledIn;

    return [
      const CSxSectionHeader(title: 'What is being captured'),
      CSxKeyValue(rows: [
        ('levels', '${logging.minimumLevel.name} and above', null),
        (
          'sampling',
          local >= 1 && remote == null
              ? 'everything'
              : '${(_effective(local, remote) * 100).round()}% · ${kept ? 'kept' : 'not this launch'}',
          kept ? null : CSxColors.warning,
        ),
        if (local < 1 || remote != null)
          ('  app asks', '${(local * 100).round()}%', CSxColors.muted),
        if (remote != null) ('  server caps', '${(remote * 100).round()}%', CSxColors.muted),
        (
          'redaction',
          redaction.headers.isEmpty && redaction.bodyKeys.isEmpty
              ? 'nothing'
              : '${redaction.headers.length} headers · ${redaction.bodyKeys.length} keys',
          redaction.headers.isEmpty && redaction.bodyKeys.isEmpty ? CSxColors.muted : null,
        ),
        ('buffer', '${LogBuffer.i.length} / ${LogBuffer.maxEntries}', null),
      ]),
      if (!kept)
        const CSxHint(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: 'Sampling is drawn '),
            TextSpan(
              text: 'once per launch',
              style: TextStyle(color: CSxColors.white, fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: ', so this will not change until the app restarts. The overlay still shows '
                  'everything. It is the upload that is skipped.',
            ),
          ])),
        ),
    ];
  }

  List<Widget> _upload(ProjectCredentials? creds, Duration? waiting) {
    if (creds == null) return [];
    return [
      const CSxSectionHeader(title: 'Upload'),
      CSxKeyValue(rows: [
        ('waiting', _pending < 0 ? 'not known' : '$_pending', _pending < 0 ? CSxColors.muted : null),
        (
          'state',
          waiting != null
              ? 'paused, retrying in ${_short(waiting)}'
              : LogSyncWorker.i.isRunning
                  ? 'uploading'
                  : 'not running',
          waiting != null ? CSxColors.warning : null,
        ),
      ]),
      if (waiting != null)
        const CSxHint(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: 'Nothing is lost. Logs stay on the device until an upload succeeds, '
                'and the pause '),
            TextSpan(
              text: 'ends by itself',
              style: TextStyle(color: CSxColors.white, fontWeight: FontWeight.w600),
            ),
            TextSpan(text: '. The SDK does not stop syncing for the rest of the launch.'),
          ])),
        ),
    ];
  }

  List<Widget> _launch(SessionRecord? session) {
    return [
      CSxSectionHeader(
        title: 'This launch',
        trailing: CSxSmallButton(
          label: 'Copy all',
          onTap: () => copyAndTell(context, _report(), 'Report'),
        ),
      ),
      CSxKeyValue(rows: [
        ('session', _short8(CodeScout.instance.currentSessionId), null),
        ('install', _short8(session?.installationId ?? '—'), null),
        ('user', session?.userId ?? 'anonymous', session?.userId == null ? CSxColors.muted : null),
        ('device', _device(session), null),
        ('app', _app(session), null),
        ('sdk', codeScoutSdkVersion, null),
      ]),
    ];
  }

  // -- the bug report --------------------------------------------------------

  String _report() {
    final creds = CodeScout.instance.configuration.projectCredentials;
    final session = CodeScout.instance.currentSession;
    final out = StringBuffer()
      ..writeln('Code Scout')
      ..writeln('session ${CodeScout.instance.currentSessionId}')
      ..writeln('install ${session?.installationId ?? '—'}')
      ..writeln('user    ${session?.userId ?? 'anonymous'}')
      ..writeln('device  ${_device(session)}')
      ..writeln('app     ${_app(session)}')
      ..writeln('sdk     $codeScoutSdkVersion')
      ..writeln('server  ${creds == null ? 'local only' : creds.link}')
      ..writeln('project ${creds?.projectName ?? '—'}')
      ..writeln('state   ${creds?.outcome.name ?? 'unconfigured'}')
      ..writeln('sampled ${CodeScout.instance.isSessionSampledIn ? 'kept' : 'not this launch'}')
      ..writeln('waiting ${_pending < 0 ? 'unknown' : _pending}');
    return out.toString().trimRight();
  }

  static double _effective(double local, double? remote) {
    if (remote == null) return local;
    // The SDK takes the lower of the two: a server can only ever make an app
    // quieter, never louder than its developer agreed to.
    return local < remote ? local : remote;
  }

  static String _device(SessionRecord? s) {
    if (s == null) return '—';
    final os = [s.osName, s.osVersion].where((p) => p != null && p.isNotEmpty).join(' ');
    final model = s.deviceModel ?? 'unknown device';
    return os.isEmpty ? model : '$model · $os';
  }

  static String _app(SessionRecord? s) {
    if (s == null || (s.appVersion == null && s.buildNumber == null)) return '—';
    final build = s.buildNumber;
    return build == null ? s.appVersion! : '${s.appVersion}+$build';
  }

  static String _short8(String id) =>
      id.length <= 12 ? id : '${id.substring(0, 4)}…${id.substring(id.length - 4)}';

  static String _short(Duration d) =>
      d.inSeconds >= 60 ? '${d.inMinutes}m ${d.inSeconds % 60}s' : '${d.inSeconds}s';
}

// ---------------------------------------------------------------------------

enum _Tone { ok, warn, bad, busy }

class _Verdict extends StatelessWidget {
  const _Verdict({
    required this.tone,
    required this.title,
    required this.detail,
    this.strong,
  });

  final _Tone tone;
  final String title;
  final String detail;
  final String? strong;

  @override
  Widget build(BuildContext context) {
    final (colour, glyph) = switch (tone) {
      _Tone.ok => (CSxColors.debug, Icons.check),
      _Tone.warn => (CSxColors.warning, Icons.circle),
      _Tone.bad => (CSxColors.error, Icons.close),
      _Tone.busy => (CSxColors.white, Icons.sync),
    };

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone == _Tone.busy ? CSxColors.card : colour.withValues(alpha: 0.10),
        border: Border.all(
          color: tone == _Tone.busy ? CSxColors.borderStrong : colour.withValues(alpha: 0.40),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(glyph, size: 14, color: colour),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: title, style: TextStyle(color: colour)),
                    if (strong != null)
                      TextSpan(
                        text: ' to $strong',
                        style: const TextStyle(
                          color: CSxColors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ]),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 4),
              child: Text(
                detail,
                style: const TextStyle(color: CSxColors.muted, fontSize: 11.5),
              ),
            ),
        ],
      ),
    );
  }
}

enum _StepState { ok, bad, skipped, busy }

class _Steps extends StatelessWidget {
  const _Steps({required this.steps});

  final List<(_StepState, String, String?)> steps;

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
          for (var i = 0; i < steps.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                border: i == steps.length - 1
                    ? null
                    : const Border(bottom: BorderSide(color: CSxColors.border)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    child: Icon(
                      switch (steps[i].$1) {
                        _StepState.ok => Icons.check,
                        _StepState.bad => Icons.close,
                        _StepState.busy => Icons.sync,
                        _StepState.skipped => Icons.remove,
                      },
                      size: 13,
                      color: switch (steps[i].$1) {
                        _StepState.ok => CSxColors.debug,
                        _StepState.bad => CSxColors.error,
                        _StepState.busy => CSxColors.primary,
                        _StepState.skipped => CSxColors.muted,
                      },
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      steps[i].$2,
                      style: TextStyle(
                        color: steps[i].$1 == _StepState.skipped
                            ? CSxColors.muted
                            : CSxColors.white,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  if (steps[i].$3 != null)
                    Flexible(
                      child: Text(
                        steps[i].$3!,
                        textAlign: TextAlign.right,
                        style: mono.copyWith(
                          color: steps[i].$1 == _StepState.bad
                              ? CSxColors.error
                              : CSxColors.muted,
                          fontSize: 10.5,
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
