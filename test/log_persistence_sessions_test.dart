import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/log/log_persistence_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Runs against a real SQLite through the ffi driver, because the behaviour
/// under test is the SQL: which sessions a batch pulls, and which ones are safe
/// to drop afterwards.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await LogPersistenceService.i.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase('$dir/code_scout.db');
  });

  tearDown(() async {
    await LogPersistenceService.i.close();
  });

  SessionRecord session(String id, {String? user}) {
    final now = DateTime.now().toUtc();
    return SessionRecord(
      id: id,
      installationId: 'install-1',
      userId: user,
      deviceModel: 'Pixel 7',
      osName: 'Android',
      osVersion: '14',
      startedAt: now,
      lastSeenAt: now,
    );
  }

  Future<void> insertLog(String id, String sessionId) async {
    final db = await LogPersistenceService.i.database;
    await db.insert('logs', {
      'id': id,
      'session_id': sessionId,
      'level': 'info',
      'message': 'hello',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'is_network_call': 0,
      'sync_status': 0,
    });
  }

  // Written once, then the same value forever. A new one per launch would make
  // every launch look like a different phone.
  test('the installation id is generated once and kept', () async {
    final first = await LogPersistenceService.i.installationId();
    final second = await LogPersistenceService.i.installationId();

    expect(first, isNotEmpty);
    expect(second, first);

    // And it survives the database being closed and reopened, which is what an
    // app restart looks like from here.
    await LogPersistenceService.i.close();
    expect(await LogPersistenceService.i.installationId(), first);
  });

  test('a session round trips through the table', () async {
    await LogPersistenceService.i.saveSession(session('s-1', user: 'u_8812'));

    final found = await LogPersistenceService.i.getSessionsByIds(['s-1']);
    expect(found, hasLength(1));
    expect(found.first.userId, 'u_8812');
    expect(found.first.deviceModel, 'Pixel 7');
  });

  test('saving again replaces rather than duplicating', () async {
    await LogPersistenceService.i.saveSession(session('s-1'));
    await LogPersistenceService.i.saveSession(session('s-1', user: 'u_8812'));

    final found = await LogPersistenceService.i.getSessionsByIds(['s-1']);
    expect(found, hasLength(1), reason: 'setUser mid-session must not fork the row');
    expect(found.first.userId, 'u_8812');
  });

  // The case that makes local session storage worth having: a launch that was
  // killed before it could sync. Its logs are still here, so its session has to
  // be too, or those logs land on the dashboard with no device and no user.
  test('a batch pulls the sessions of previous launches too', () async {
    await LogPersistenceService.i.saveSession(session('s-old', user: 'u_8812'));
    await LogPersistenceService.i.saveSession(session('s-now'));

    final found =
        await LogPersistenceService.i.getSessionsByIds(['s-old', 's-now']);
    expect(found.map((s) => s.id).toSet(), {'s-old', 's-now'});
  });

  test('pruning drops finished sessions and keeps the live one', () async {
    await LogPersistenceService.i.saveSession(session('s-old'));
    await LogPersistenceService.i.saveSession(session('s-busy'));
    await LogPersistenceService.i.saveSession(session('s-now'));
    // s-busy still has an unsynced log, so it is not finished.
    await insertLog('log-1', 's-busy');

    await LogPersistenceService.i.pruneSessions('s-now');

    final left = await LogPersistenceService.i
        .getSessionsByIds(['s-old', 's-busy', 's-now']);
    expect(
      left.map((s) => s.id).toSet(),
      {'s-busy', 's-now'},
      reason: 's-old has no logs left and is not current, so only it should go',
    );
  });

  // The current launch has no logs the instant a sync succeeds, but it is
  // still running. Dropping it would lose the device on everything it logs
  // from then on.
  test('the live session survives having no logs', () async {
    await LogPersistenceService.i.saveSession(session('s-now'));
    await LogPersistenceService.i.pruneSessions('s-now');

    expect(await LogPersistenceService.i.getSessionsByIds(['s-now']), hasLength(1));
  });

  test('asking for nothing returns nothing rather than everything', () async {
    await LogPersistenceService.i.saveSession(session('s-1'));
    expect(await LogPersistenceService.i.getSessionsByIds([]), isEmpty);
  });

  // The number the overlay shows next to "Waiting to upload". It counts what is
  // still on disk, including a batch already marked in-flight — that batch has
  // not arrived anywhere yet, and rows are only deleted once the server has
  // taken them.
  test('pendingCount counts everything still on disk', () async {
    expect(await LogPersistenceService.i.pendingCount(), 0);

    await LogPersistenceService.i.saveLogEntry(
        LogEntry(level: LogLevel.info, message: 'one', sessionID: 's-1'));
    await LogPersistenceService.i.saveLogEntry(
        LogEntry(level: LogLevel.info, message: 'two', sessionID: 's-1'));
    expect(await LogPersistenceService.i.pendingCount(), 2);

    final rows = await LogPersistenceService.i.getLogEntries();
    final ids = rows.map((r) => r['id'] as String).toList();

    // Marked as syncing is still waiting: the upload can fail and roll back.
    await LogPersistenceService.i.markAsSyncing(ids);
    expect(await LogPersistenceService.i.pendingCount(), 2,
        reason: 'a batch in flight has not reached the server yet');

    await LogPersistenceService.i.deleteLogEntries(ids);
    expect(await LogPersistenceService.i.pendingCount(), 0,
        reason: 'the server took them, so nothing is waiting');
  });
}
