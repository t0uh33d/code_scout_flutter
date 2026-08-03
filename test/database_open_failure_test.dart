import 'package:code_scout/src/log/log_persistence_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A database that will not open is something every caller in the SDK already
/// handles: the session is skipped, the log is dropped, the app carries on. It
/// must not also surface as an unhandled async error, because that is a crash
/// report with Code Scout's name on it for a problem Code Scout absorbed.
///
/// No `databaseFactory` is set anywhere in this file on purpose — that is what
/// makes opening fail. Each test file is its own isolate, so nothing another
/// file does can accidentally make this one pass.
void main() {
  test('a database that cannot open fails the caller, not the zone', () async {
    await expectLater(
      LogPersistenceService.i.database,
      throwsA(isA<StateError>()),
    );

    // The caller's copy of the error was handled by expectLater. The completer
    // holds a second copy for anyone who asked while the open was in flight,
    // and if that one goes unobserved the test framework reports it once the
    // microtask queue drains — after this line, failing the test.
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
}
