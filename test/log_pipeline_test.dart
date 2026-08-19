import 'dart:async';

import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout/src/live/live_session_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Three settings that were declared and then not honoured by anything.
void main() {
  setUp(LogBuffer.i.clear);
  tearDown(() {
    LogBuffer.i.clear();
    CodeScout.instance.configuration = CodeScoutConfiguration();
  });

  /// Captures whatever the SDK writes to the platform console during [body].
  Future<List<String>> consoleOutput(Future<void> Function() body) async {
    final printed = <String>[];
    await runZoned(body, zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => printed.add(line),
    ));
    return printed;
  }

  group('printToConsole', () {
    // It was read from kDebugMode into a field that nothing ever consulted, so
    // every release build printed every log to the console no matter what the
    // app asked for.
    test('false means nothing reaches the console', () async {
      CodeScout.instance.configuration = CodeScoutConfiguration(
        logging: LoggingBehavior(minimumLevel: LogLevel.all, printToConsole: false),
      );

      final printed = await consoleOutput(() async {
        await LogEntry(
          level: LogLevel.info,
          message: 'should not be printed',
          sessionID: 's',
        ).processLogEntry();
      });

      expect(printed.join('\n'), isNot(contains('should not be printed')));
    });

    test('true still prints', () async {
      CodeScout.instance.configuration = CodeScoutConfiguration(
        logging: LoggingBehavior(minimumLevel: LogLevel.all, printToConsole: true),
      );

      final printed = await consoleOutput(() async {
        await LogEntry(
          level: LogLevel.info,
          message: 'should be printed',
          sessionID: 's',
        ).processLogEntry();
      });

      expect(printed.join('\n'), contains('should be printed'));
    });

    // Turning the console off must not turn the SDK off. The overlay reads the
    // buffer, and it is the thing you are looking at while you work.
    test('a silent console still fills the in-app buffer', () async {
      CodeScout.instance.configuration = CodeScoutConfiguration(
        logging: LoggingBehavior(minimumLevel: LogLevel.all, printToConsole: false),
      );

      await LogEntry(level: LogLevel.info, message: 'quiet', sessionID: 's')
          .processLogEntry();

      expect(LogBuffer.i.length, 1);
    });
  });

  group('logMessage', () {
    // The whole pipeline was wrapped in a catch that reported to
    // dart:developer and returned, so awaiting told you nothing. The doc
    // comment said to use it "if you need to await persistence".
    test('throws when the write fails', () async {
      // An uploader has to be configured for the write to be attempted at
      // all: with none, processLogEntry returns before SQLite, because a row
      // nothing can ever upload would only accumulate on the device.
      CodeScout.instance.configuration = CodeScoutConfiguration(
        logging: LoggingBehavior(minimumLevel: LogLevel.all, printToConsole: false),
        projectCredentials: ProjectCredentials(
          link: 'https://scout.example.dev/',
          projectID: 'a3f2c7d1-4e88-4b21-9f60-1c2d3e4f9c41',
          projectSecret: 'secret',
        ),
        sync: LogSyncBehavior(syncInterval: const Duration(seconds: 30)),
      );

      // No database is initialised in a plain test, so the write cannot land.
      await expectLater(
        CodeScout.instance.logMessage(level: LogLevel.info, message: 'did this store?'),
        throwsA(anything),
      );
    });

    // A dropped log is the configuration working, not a failure, so the caller
    // must not have to tell the two apart with a try/catch.
    test('a log the level gate drops returns normally', () async {
      CodeScout.instance.configuration = CodeScoutConfiguration(
        logging: LoggingBehavior(minimumLevel: LogLevel.error, printToConsole: false),
      );

      await expectLater(
        CodeScout.instance.logMessage(level: LogLevel.debug, message: 'too quiet to matter'),
        completes,
      );
    });

    // The shorthand keeps swallowing. A logging call is not a place an app
    // should be able to fall over.
    test('the fire and forget shorthand never throws', () async {
      CodeScout.instance.configuration = CodeScoutConfiguration(
        logging: LoggingBehavior(minimumLevel: LogLevel.all, printToConsole: false),
      );

      expect(() => CodeScout.instance.i('no database here'), returnsNormally);
    });
  });

  // Third setting of the same kind: declared, defaulted, and read by nothing.
  // An app that turns live streaming off is saying it never wants to be
  // watched, and that has to hold for a caller who reaches past the panel.
  group('enableLiveStreaming', () {
    // Asserting only that it returns false proves nothing, because a failed
    // connection returns false too. That version passed with the guard
    // deleted. What separates the two is whether the client is asked to
    // connect at all, so this counts the state changes instead.
    test('false refuses without even trying to connect', () async {
      CodeScout.instance.configuration = CodeScoutConfiguration(
        // Credentials present, so the flag is the only thing in the way.
        projectCredentials: ProjectCredentials(
          link: 'http://localhost:1/',
          projectID: 'p',
          projectSecret: 's',
        ),
        realTime: RealTimeConfig(enableLiveStreaming: false),
      );

      var notifications = 0;
      void count() => notifications++;
      LiveSessionClient.i.addListener(count);
      addTearDown(() => LiveSessionClient.i.removeListener(count));

      expect(await CodeScout.instance.startLiveSession('4K7Q2P'), isFalse);
      expect(LiveSessionClient.i.state, LiveSessionState.idle);
      expect(notifications, 0, reason: 'it never moved to connecting');
    });

    test('the default leaves it available', () {
      CodeScout.instance.configuration = CodeScoutConfiguration();
      expect(CodeScout.instance.configuration.realTime.enableLiveStreaming, isTrue);
    });
  });
}
