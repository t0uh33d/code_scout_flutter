import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout/src/log/log_persistence_service.dart';
import 'package:code_scout/src/log/log_sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite is the sync worker's queue, and a row is only deleted once its batch
/// has uploaded. So whether a log may be written comes down to whether an
/// upload could ever happen: with no uploader the table only grows, forever, on
/// a phone that belongs to somebody else.
///
/// Both of these are ordinary configurations rather than mistakes to shrug at.
/// Local mode is documented as a real way to use the SDK, and leaving out the
/// `sync:` block is the single most common setup slip there is.
void main() {
  final creds = ProjectCredentials(
    link: 'https://scout.example.dev/',
    projectID: 'a3f2c7d1-4e88-4b21-9f60-1c2d3e4f9c41',
    projectSecret: 'secret',
  );

  group('canUpload', () {
    tearDown(() {
      CodeScout.instance.configuration = CodeScoutConfiguration();
    });

    test('local mode cannot upload', () {
      CodeScout.instance.configuration = CodeScoutConfiguration(
        logging: LoggingBehavior(minimumLevel: LogLevel.all),
      );
      expect(LogSyncWorker.i.canUpload, isFalse);
    });

    test('credentials without a sync block cannot upload', () {
      CodeScout.instance.configuration =
          CodeScoutConfiguration(projectCredentials: creds);
      expect(LogSyncWorker.i.canUpload, isFalse,
          reason: 'there is no default interval, so nothing would drain it');
    });

    test('a sync block with no credentials cannot upload', () {
      CodeScout.instance.configuration = CodeScoutConfiguration(
        sync: LogSyncBehavior(syncInterval: const Duration(seconds: 30)),
      );
      expect(LogSyncWorker.i.canUpload, isFalse);
    });

    test('both configured is the one case that may write', () {
      CodeScout.instance.configuration = CodeScoutConfiguration(
        projectCredentials: creds,
        sync: LogSyncBehavior(syncInterval: const Duration(seconds: 30)),
      );
      expect(LogSyncWorker.i.canUpload, isTrue);
    });
  });

  // The group above only proves the predicate is right. It says nothing about
  // whether the write path consults it, and an earlier version of this file
  // stopped there: removing the gate from processLogEntry entirely left every
  // test in it passing. These drive the real pipeline against a real database.
  group('what actually reaches SQLite', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      await LogPersistenceService.i.close();
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase('$dir/code_scout.db');
      LogBuffer.i.clear();
      CodeScout.instance.isSessionSampledIn = true;
    });

    tearDown(() async {
      await LogPersistenceService.i.close();
      CodeScout.instance.configuration = CodeScoutConfiguration();
    });

    Future<int> storedLogCount() async {
      final db = await LogPersistenceService.i.database;
      return (await db.query('logs')).length;
    }

    Future<void> logOnce() => LogEntry(
          level: LogLevel.error,
          message: 'payment declined',
          sessionID: 's-1',
        ).processLogEntry();

    test('local mode writes nothing at all', () async {
      CodeScout.instance.configuration = CodeScoutConfiguration(
        logging: LoggingBehavior(minimumLevel: LogLevel.all),
      );

      await logOnce();
      await logOnce();
      await logOnce();

      expect(await storedLogCount(), 0,
          reason: 'nothing can ever upload these, and nothing ever reads them '
              'back, so every one would sit on the device for good');
    });

    test('credentials with no sync block write nothing either', () async {
      CodeScout.instance.configuration =
          CodeScoutConfiguration(projectCredentials: creds);

      await logOnce();

      expect(await storedLogCount(), 0);
    });

    test('a configured uploader writes as it always did', () async {
      CodeScout.instance.configuration = CodeScoutConfiguration(
        projectCredentials: creds,
        sync: LogSyncBehavior(syncInterval: const Duration(seconds: 30)),
      );

      await logOnce();

      expect(await storedLogCount(), 1,
          reason: 'the queue still has to work when there is something to '
              'drain it');
    });

    test('the console and the on-device panel are unaffected', () async {
      CodeScout.instance.configuration = CodeScoutConfiguration(
        logging: LoggingBehavior(minimumLevel: LogLevel.all),
      );

      await logOnce();

      expect(LogBuffer.i.length, 1,
          reason: 'local mode is a real way to use the SDK: the overlay is '
              'served from memory and must keep working with nothing stored');
      expect(await storedLogCount(), 0);
    });
  });
}
