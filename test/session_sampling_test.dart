import 'dart:io';

import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout/src/log/log_persistence_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Sampling is the one setting a server can change on an app already in
/// people's hands, so the rule that matters is which way it is allowed to move
/// it: down, never up.
void main() {
  group('effectiveSampleRate', () {
    test('with no word from the server the app keeps its own rate', () {
      final b = LoggingBehavior(sessionSampleRate: 0.3);
      expect(b.effectiveSampleRate(null), 0.3);
      expect(b.effectiveSampleRate(), 0.3);
    });

    test('the server can lower the rate', () {
      final b = LoggingBehavior(sessionSampleRate: 1.0);
      expect(b.effectiveSampleRate(0.1), 0.1);
    });

    // The load-bearing one. A compromised or simply misconfigured server must
    // not be able to turn an app into a firehose its developer never agreed to.
    test('the server cannot raise it', () {
      final b = LoggingBehavior(sessionSampleRate: 0.05);
      expect(b.effectiveSampleRate(1.0), 0.05);
      expect(b.effectiveSampleRate(0.9), 0.05);
    });

    test('zero from either side means zero', () {
      expect(LoggingBehavior(sessionSampleRate: 0).effectiveSampleRate(1.0), 0);
      expect(LoggingBehavior(sessionSampleRate: 1).effectiveSampleRate(0), 0);
    });

    // Nothing outside 0..1 can survive, from either side. A rate of 3.0 read as
    // "300%" would be harmless; a rate of -1 read literally would not.
    test('both sides are clamped into range', () {
      expect(LoggingBehavior(sessionSampleRate: 5).effectiveSampleRate(null), 1.0);
      expect(LoggingBehavior(sessionSampleRate: -2).effectiveSampleRate(null), 0.0);
      expect(LoggingBehavior(sessionSampleRate: 1).effectiveSampleRate(7), 1.0);
      expect(LoggingBehavior(sessionSampleRate: 1).effectiveSampleRate(-7), 0.0);
    });

    // A NaN is a broken number, not an instruction to stop logging.
    test('a NaN falls back to recording everything', () {
      expect(LoggingBehavior(sessionSampleRate: double.nan).effectiveSampleRate(null), 1.0);
      expect(LoggingBehavior(sessionSampleRate: 1).effectiveSampleRate(double.nan), 1.0);
    });
  });

  group('the default', () {
    test('an app that has not asked for sampling records everything', () {
      expect(LoggingBehavior().sessionSampleRate, 1.0);
      expect(LoggingBehavior().effectiveSampleRate(null), 1.0);
    });
  });

  group('drawSession', () {
    // Both ends short-circuit. 1.0 is what almost every app runs at, and it
    // must not depend on a random number landing right.
    test('the ends do not depend on the draw', () {
      double never() => fail('the draw should not have been consulted');
      expect(drawSession(1.0, random: never), isTrue);
      expect(drawSession(0.0, random: never), isFalse);
      expect(drawSession(2.0, random: never), isTrue);
      expect(drawSession(-1, random: never), isFalse);
    });

    test('in between, the draw decides', () {
      expect(drawSession(0.25, random: () => 0.1), isTrue);
      expect(drawSession(0.25, random: () => 0.25), isFalse,
          reason: 'the boundary belongs to the excluded side, or 0.25 would keep slightly more than a quarter');
      expect(drawSession(0.25, random: () => 0.9), isFalse);
    });
  });

  // The gate itself. Sampling is only worth anything if it actually stops the
  // write, and it is only tolerable if it stops nothing else — a developer
  // watching the console or the overlay must see their logs whether or not
  // this launch is one of the recorded ones.
  group('the gate in processLogEntry', () {
    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      // Its own directory. Test files run in parallel and the service always
      // opens code_scout.db by the same name, so sharing the default path lets
      // this file's setUp delete the database another file is midway through
      // using. The failures land over there, which makes them hard to read.
      await databaseFactory
          .setDatabasesPath(Directory.systemTemp.createTempSync('cs-sampling').path);
    });

    setUp(() async {
      await LogPersistenceService.i.close();
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase('$dir/code_scout.db');
      LogBuffer.i.clear();
    });

    tearDown(() async {
      await LogPersistenceService.i.close();
      CodeScout.instance.isSessionSampledIn = true;
    });

    Future<int> storedLogCount() async {
      final db = await LogPersistenceService.i.database;
      final rows = await db.query('logs');
      return rows.length;
    }

    test('a sampled-in launch is written', () async {
      CodeScout.instance.isSessionSampledIn = true;

      await LogEntry(
        level: LogLevel.error,
        message: 'kept',
        sessionID: 's-1',
      ).processLogEntry();

      expect(await storedLogCount(), 1);
    });

    test('a sampled-out launch writes nothing', () async {
      CodeScout.instance.isSessionSampledIn = false;

      await LogEntry(
        level: LogLevel.error,
        message: 'dropped',
        sessionID: 's-1',
      ).processLogEntry();

      expect(await storedLogCount(), 0,
          reason: 'sampling that still writes the row saves nobody anything');
    });

    test('a sampled-out launch still fills the overlay', () async {
      CodeScout.instance.isSessionSampledIn = false;

      await LogEntry(
        level: LogLevel.error,
        message: 'still visible on device',
        sessionID: 's-1',
      ).processLogEntry();

      expect(LogBuffer.i.entries.map((e) => e.message), contains('still visible on device'),
          reason: 'the overlay costs nothing to fill and is what you are looking at while you work');
    });
  });
}
