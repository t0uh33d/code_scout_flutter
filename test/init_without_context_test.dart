import 'dart:io';

import 'package:code_scout/code_scout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// `freshContextFetcher` is optional, so an app is free to call `init()` before
/// it has a widget tree — during `main()`, ahead of `runApp`, which is exactly
/// where you want logging to start. That left the overlay with no context to
/// insert itself into.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('cs-init').path);
  });

  tearDownAll(() async {
    await CodeScout.instance.dispose();
  });

  test('init with no context does not throw placing the overlay', () async {
    await CodeScout.instance.init();

    // The failure was asynchronous. createOverlayEntry schedules the insert for
    // the next turn of the event loop, so init() returned cleanly and the throw
    // arrived afterwards, in a callback with nobody to catch it.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(CodeScout.instance.isInitialized, isTrue);
  });
}
