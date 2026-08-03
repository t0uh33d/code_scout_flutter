import 'dart:convert';
import 'dart:io';

import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/live/live_session_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Live streaming is the one thing in this SDK that talks to the server over
/// something other than an HTTP request, so the tests run a real socket server
/// rather than a mock: the pairing frame the server reads is the contract, and
/// a mock would only prove the SDK agrees with itself.
void main() {
  group('the socket URL', () {
    // The base link is an http URL because everything else the SDK does is
    // HTTP. Deriving the socket URL from it is the one place a mistake would
    // silently downgrade a TLS instance to a plaintext socket.
    test('http becomes ws and https becomes wss', () {
      expect(socketUrlFor('http://localhost:24275/'), 'ws://localhost:24275/api/live/socket');
      expect(socketUrlFor('https://scout.team.dev/'), 'wss://scout.team.dev/api/live/socket');
    });

    test('a subpath is kept', () {
      expect(
        socketUrlFor('https://team.dev/code-scout/'),
        'wss://team.dev/code-scout/api/live/socket',
      );
    });

    test('a port is kept', () {
      expect(socketUrlFor('https://team.dev:8443/'), 'wss://team.dev:8443/api/live/socket');
    });
  });

  group('pairing', () {
    late HttpServer server;
    late String link;

    // The publish tests drive the real logging path, which writes to SQLite on
    // the way past. Its own databases directory: test files run in parallel
    // and the service always opens code_scout.db by that one name, so sharing
    // the default path lets one file delete a database another is using.
    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory
          .setDatabasesPath(Directory.systemTemp.createTempSync('cs-live').path);
    });
    // What the server was told, so the test can assert on the real frame
    // rather than on what the client thinks it sent.
    Map<String, dynamic>? hello;
    List<Map<String, dynamic>> frames = [];
    bool accept = true;

    setUp(() async {
      hello = null;
      frames = [];
      accept = true;

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      link = 'http://127.0.0.1:${server.port}/';

      server.listen((request) async {
        if (!WebSocketTransformer.isUpgradeRequest(request)) {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
          return;
        }
        // The credentials are checked before the code is ever read, exactly as
        // the real server does it.
        if (request.headers.value('X-Project-ID') == null) {
          request.response.statusCode = HttpStatus.unauthorized;
          await request.response.close();
          return;
        }

        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((raw) {
          final message = jsonDecode(raw as String) as Map<String, dynamic>;
          if (hello == null) {
            hello = message;
            socket.add(jsonEncode(accept
                ? {'ok': true, 'session_id': 'live-session-1'}
                : {'ok': false, 'error': 'that code is not valid'}));
            if (!accept) socket.close();
            return;
          }
          frames.add(message);
        });
      });
    });

    tearDown(() async {
      await LiveSessionClient.i.stop();
      await server.close(force: true);
    });

    CodeScoutConfiguration configured() => CodeScoutConfiguration(
          projectCredentials: ProjectCredentials(
            link: link,
            projectID: 'project-1',
            projectSecret: 'secret-1',
          ),
        );

    Future<bool> start(String code) => LiveSessionClient.i.start(
          code: code,
          configuration: configured(),
          currentSessionId: 'launch-1',
          session: SessionRecord(
            id: 'launch-1',
            installationId: 'install-1',
            deviceModel: 'Pixel 7',
            osName: 'Android',
            osVersion: '14',
            appVersion: '3.11.2',
            buildNumber: '418',
            startedAt: DateTime.now().toUtc(),
            lastSeenAt: DateTime.now().toUtc(),
          ),
        );

    test('the code and the device go up in the first frame', () async {
      expect(await start('4K7Q2P'), isTrue);

      expect(hello, isNotNull);
      expect(hello!['code'], '4K7Q2P');

      // Snake case, matching the server's LiveDevice. Camel case here would be
      // silently dropped and every device would render as "Unknown device".
      final device = hello!['device'] as Map<String, dynamic>;
      expect(device['session_id'], 'launch-1');
      expect(device['installation_id'], 'install-1');
      expect(device['device_model'], 'Pixel 7');
      expect(device['os_name'], 'Android');
      expect(device['os_version'], '14');
      expect(device['app_version'], '3.11.2');
      expect(device['build_number'], '418');
    });

    test('the client goes live once the server accepts', () async {
      expect(await start('4K7Q2P'), isTrue);
      expect(LiveSessionClient.i.state, LiveSessionState.live);
      expect(LiveSessionClient.i.isLive, isTrue);
      expect(LiveSessionClient.i.sessionId, 'live-session-1');
      expect(LiveSessionClient.i.error, isNull);
    });

    // A refusal is the common case — codes are typed by hand and expire — so
    // it has to end somewhere a person can act on, not in an exception.
    test('a refused code fails with the reason and never throws', () async {
      accept = false;

      expect(await start('ZZZZZZ'), isFalse);
      expect(LiveSessionClient.i.isLive, isFalse);
      expect(LiveSessionClient.i.error, 'that code is not valid');
      expect(LiveSessionClient.i.state, LiveSessionState.ended);
    });

    test('a server that is not there fails rather than hanging', () async {
      // Port 1 is reserved and nothing listens on it.
      final ok = await LiveSessionClient.i.start(
        code: '4K7Q2P',
        configuration: CodeScoutConfiguration(
          projectCredentials: ProjectCredentials(
            link: 'http://127.0.0.1:1/',
            projectID: 'p',
            projectSecret: 's',
          ),
        ),
        currentSessionId: 'launch-1',
      );

      expect(ok, isFalse);
      expect(LiveSessionClient.i.error, isNotNull);
    });

    test('with no credentials it refuses and says why', () async {
      final ok = await LiveSessionClient.i.start(
        code: '4K7Q2P',
        configuration: CodeScoutConfiguration(),
        currentSessionId: 'launch-1',
      );

      expect(ok, isFalse);
      expect(LiveSessionClient.i.error, contains('credentials'));
    });

    // The wire shape a watcher renders. The upload format is deliberately not
    // reused, so this is the only thing pinning it.
    test('a published log arrives in the shape the dashboard reads', () async {
      expect(await start('4K7Q2P'), isTrue);

      await CodeScout.instance.logMessage(
        level: LogLevel.error,
        message: 'payment declined',
      );

      await _until(() => frames.any((f) => (f['logs'] as List).isNotEmpty));

      final logs = frames
          .expand((f) => (f['logs'] as List).cast<Map<String, dynamic>>())
          .toList();
      expect(logs, isNotEmpty);
      expect(logs.first['level'], 'error');
      expect(logs.first['message'], 'payment declined');
      expect(logs.first['timestamp'], isA<String>());
      // Parseable as ISO-8601, or every row renders with a blank time.
      expect(DateTime.tryParse(logs.first['timestamp'] as String), isNotNull);
    });

    test('nothing is sent once the session is stopped', () async {
      expect(await start('4K7Q2P'), isTrue);
      await LiveSessionClient.i.stop();

      expect(LiveSessionClient.i.isLive, isFalse);
      final before = frames.length;

      await CodeScout.instance.logMessage(
        level: LogLevel.error,
        message: 'after the session ended',
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(frames.length, before,
          reason: 'a stopped session must not keep streaming');
    });

    // publish() is called on every log, so it has to be free when nobody is
    // watching. This is the guard against the live path ever throwing into the
    // logging path.
    test('publishing with no session is a no-op', () async {
      expect(LiveSessionClient.i.isLive, isFalse);
      await CodeScout.instance.logMessage(
        level: LogLevel.info,
        message: 'nobody is watching',
      );
      expect(LiveSessionClient.i.state, LiveSessionState.idle);
    });
  });
}

/// Polls until [ready] or gives up, so a test never hangs on a frame that is
/// never coming.
Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
