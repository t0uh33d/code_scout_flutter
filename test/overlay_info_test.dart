import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/info_tab.dart';
import 'package:code_scout/src/csx_interface/menu.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Info answers one question at two moments: is this reaching my dashboard,
/// and is this being recorded. Both are answered by the line at the top, so
/// that line has to be right in every state.
void main() {
  setUp(() {
    NetworkManager.i.resetIntegrations();
    DatabaseRegistry.i.clear();
    // TestWidgetsFlutterBinding installs an HttpOverrides that answers every
    // request with 400 without opening a socket, which turns "nothing is
    // listening" into "the server refused". Clearing it lets the unreachable
    // path actually be exercised.
    HttpOverrides.global = null;
  });
  tearDown(DatabaseRegistry.i.clear);

  Future<void> pump(WidgetTester tester) async {
    // Tall, because the screen is one lazy ListView and half of what these
    // tests assert on is below the fold of a default 600px surface.
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: _Host(child: InfoScreen()),
      ),
    ));
    await tester.pump();
  }

  group('the verdict', () {
    testWidgets('local mode is a supported setup, not a failure', (tester) async {
      CodeScout.instance.configuration = CodeScoutConfiguration(logging: LoggingBehavior());
      await pump(tester);

      expect(find.text('Local only'), findsOneWidget);
      // A next step rather than a red cross.
      expect(find.textContaining('working setup, not a broken one'), findsOneWidget);
      expect(find.textContaining('ProjectCredentials'), findsOneWidget);
    });

    testWidgets('a sampled-out launch says it is recording nothing', (tester) async {
      CodeScout.instance.configuration = CodeScoutConfiguration(
          logging: LoggingBehavior(sessionSampleRate: 0),
          projectCredentials: ProjectCredentials(
            link: 'https://example.test/',
            projectID: 'p',
            projectSecret: 's',
          ),
        );
      // init cannot reach the server in a test, so force the one state this
      // is about.
      CodeScout.instance.isSessionSampledIn = false;
      await pump(tester);

      // Only reachable once the connection is ok, which is the point: this is
      // the state where everything reports healthy and nothing arrives.
      expect(find.textContaining('sampling'), findsOneWidget);
    });
  });

  group('test connection', () {
    testWidgets('a step that has not run does not show a cross it has not earned',
        (tester) async {
      final creds = ProjectCredentials(
        // Nothing listens here, so the check fails as unreachable.
        link: 'http://localhost:1/',
        projectID: 'p',
        projectSecret: 's',
      );
      CodeScout.instance.configuration =
          CodeScoutConfiguration(logging: LoggingBehavior(), projectCredentials: creds);

      // A real socket cannot complete inside a widget test's fake-async zone,
      // so the check runs outside it and the screen renders the result.
      await tester.runAsync(creds.check);
      expect(creds.outcome, ConnectionOutcome.unreachable);

      await pump(tester);

      expect(find.text('Cannot reach the server'), findsOneWidget);
      expect(find.text('Credentials accepted'), findsOneWidget);
      expect(find.text('Project identified'), findsOneWidget);
    });

    // The two mistakes that account for most first runs, named rather than
    // left for a search engine.
    testWidgets('localhost on a device, and cleartext on Android, are named', (tester) async {
      final creds = ProjectCredentials(
        link: 'http://localhost:1/',
        projectID: 'p',
        projectSecret: 's',
      );
      CodeScout.instance.configuration =
          CodeScoutConfiguration(logging: LoggingBehavior(), projectCredentials: creds);

      await tester.runAsync(creds.check);
      await pump(tester);

      expect(find.textContaining('localhost is the phone'), findsOneWidget);
      expect(find.textContaining('blocks plain HTTP'), findsOneWidget);
    });

    testWidgets('the secret is never shown, only its length', (tester) async {
      CodeScout.instance.configuration = CodeScoutConfiguration(
          logging: LoggingBehavior(),
          projectCredentials: ProjectCredentials(
            link: 'https://example.test/',
            projectID: 'project-id-here',
            projectSecret: 'sup3rs3cr3t-value-nobody-should-see',
          ),
        );
      await pump(tester);

      expect(find.textContaining('sup3rs3cr3t'), findsNothing,
          reason: 'this screen gets screenshotted into bug reports');
      expect(find.textContaining('35 characters'), findsOneWidget);
    });
  });

  group('what is wired up', () {
    testWidgets('an absent interceptor is a state, drawn as clearly as present',
        (tester) async {
      CodeScout.instance.configuration = CodeScoutConfiguration(logging: LoggingBehavior());
      await pump(tester);

      expect(find.text('Dio interceptor'), findsOneWidget);
      expect(find.textContaining('not installed'), findsWidgets);
      // An empty Network tab and a missing interceptor look identical without
      // this, which is the most common setup mistake and has no symptom.
      expect(find.textContaining('Network tab will stay empty'), findsOneWidget);
    });

    testWidgets('an integration that registered says so', (tester) async {
      NetworkManager.i.registerIntegration('dio');
      CodeScout.instance.configuration = CodeScoutConfiguration(logging: LoggingBehavior());
      await pump(tester);

      expect(find.textContaining('Network tab will stay empty'), findsNothing);
    });

    testWidgets('registered databases are listed with what the dashboard may do',
        (tester) async {
      CodeScout.instance.configuration = CodeScoutConfiguration(logging: LoggingBehavior());
      DatabaseRegistry.i.register('shop.db', _StubSource(), writable: true);
      DatabaseRegistry.i.register('prefs', _StubSource());
      await pump(tester);

      expect(find.text('shop.db'), findsOneWidget);
      expect(find.text('writable'), findsOneWidget);
      expect(find.text('read only'), findsOneWidget);
    });
  });
}

class _StubSource implements CodeScoutSource {
  @override
  CodeScoutSourceKind get kind => CodeScoutSourceKind.sql;

  @override
  Future<List<CodeScoutNamespace>> namespaces() async => const [];

  @override
  Future<CodeScoutSchema> describe(String namespace) async =>
      const CodeScoutSchema(namespace: 'n', columns: []);

  @override
  Future<CodeScoutPage> read(CodeScoutReadRequest request) async =>
      const CodeScoutPage(columns: [], rows: [], handles: [], hasMore: false);

  @override
  Future<CodeScoutWriteResult> write(CodeScoutWriteRequest request) async =>
      const CodeScoutWriteResult.written();
}

class _Host extends StatefulWidget {
  const _Host({required this.child});

  final Widget child;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final List<Widget> _stack = [];

  @override
  Widget build(BuildContext context) {
    return OverlayNavigator(
      push: (w) => setState(() => _stack.add(w)),
      pop: () => setState(() {
        if (_stack.isNotEmpty) _stack.removeLast();
      }),
      child: _stack.isEmpty ? widget.child : _stack.last,
    );
  }
}
