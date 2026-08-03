import 'dart:io';

import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/log/log_sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Whether the server answered in the one second the app happened to start is
/// not a good reason to stop collecting logs for the rest of the launch.
///
/// The binding stubs every request to 400 without opening a socket, so
/// validation fails here exactly as it would against a server that is down.
/// Its own file because init() can only run once per process.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('cs-sync-startup').path);
  });

  tearDownAll(() async {
    await CodeScout.instance.dispose();
  });

  test('a server that will not answer at startup does not disable sync', () async {
    await CodeScout.instance.init(
      configuration: CodeScoutConfiguration(
        projectCredentials: ProjectCredentials(
          link: 'http://127.0.0.1:1/',
          projectID: 'a-project',
          projectSecret: 'a-secret',
        ),
        sync: LogSyncBehavior(syncInterval: const Duration(minutes: 5)),
      ),
    );

    expect(
      CodeScout.instance.configuration.projectCredentials!.serverSampleRate,
      isNull,
      reason: 'the precondition: this server never answered',
    );
    expect(
      LogSyncWorker.i.isRunning,
      isTrue,
      reason: 'one unanswered request at launch must not stop the app '
          'uploading for the rest of the process — the logs are already on '
          'disk and the server may be up a second later',
    );
  });
}
