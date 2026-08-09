// The database browser, from the dashboard to a real device and back.
//
// This is the one place the two ends of that feature meet. The dashboard's
// Playwright tests drive a stub device that answers canned JSON, which proves
// the server renders a shape but not that the SDK still produces it. The
// Flutter tests open a real SQLite file with no server on the other end, which
// proves the SQL is right but not that anything asked for it. Neither notices
// when the wire format between them moves.
//
// It has already been noticed the hard way: a fix once shipped with its Go half
// committed and its SDK half not, and every dashboard test stayed green.
//
// So this one runs the real SDK, pairs it over a real WebSocket, and then asks
// the dashboard's own HTTP routes the questions a person clicking would ask. An
// assertion here fails when either side renames a field.
//
// Skipped unless CS_E2E_BASE points at a running server. `make test-sdk-e2e` in
// the code_scout repo starts a throwaway server and database and sets it.

import 'dart:io';

import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/live/live_session_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'dashboard.dart';

/// Values chosen so none of them is also valid JSON.
///
/// A form field comes back through `jsonScalar` on the server, which parses
/// what it can: `off` stays the string "off", but `true` would arrive at the
/// device as a boolean and never match the text in the column.
const _flagWas = 'off';
const _flagNow = 'on';

void main() {
  final env = Dashboard.baseFromEnvironment;
  if (env == null) {
    test('database browser', () {},
        skip: 'needs a running dashboard: set CS_E2E_BASE, '
            'or run `make test-sdk-e2e` in the code_scout repo');
    return;
  }

  final dash = Dashboard(env);
  late Database shop;
  late String sessionID;
  // The read-only store, kept here so an assertion can check the device's own
  // copy rather than only what the dashboard said about it.
  final prefs = <String, Object?>{'theme': 'dark', 'launches': 12};

  /// The dashboard's own path to a page of rows, which is what the table
  /// buttons in the schema rail link to.
  Future<Res> rows(String db, String table) =>
      dash.project('live/$sessionID/db/rows?db=$db&table=$table');

  /// One cell edit, as the editor's form posts it.
  Future<Res> save({
    required String db,
    required String table,
    required String column,
    required String handle,
    required String was,
    required String value,
  }) =>
      dash.projectForm('live/$sessionID/db/cell', {
        'db': db,
        'table': table,
        'column': column,
        'handle': handle,
        'was': was,
        'value': value,
      });

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The binding installs an HttpOverrides that answers every request with 400
    // and never opens a socket. That takes out the WebSocket this test is
    // entirely about, so it goes first.
    HttpOverrides.global = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Its own directory: the e2e files run in parallel and the persistence
    // service always opens code_scout.db under the same name.
    final scratch = Directory.systemTemp.createTempSync('cs-db-e2e');
    await databaseFactory.setDatabasesPath(scratch.path);
    installScratchPaths(scratch.path);

    await dash.signIn();
    await dash.createProject('db-e2e-${DateTime.now().millisecondsSinceEpoch}');

    await CodeScout.instance.init(
      configuration: CodeScoutConfiguration(
        logging: LoggingBehavior(minimumLevel: LogLevel.all),
        projectCredentials: ProjectCredentials(
          link: dash.base,
          projectID: dash.projectID,
          projectSecret: dash.projectSecret,
        ),
        // An hour, so the sync timer never fires and this test never races an
        // upload it did not ask for.
        sync: LogSyncBehavior(syncInterval: const Duration(hours: 1)),
      ),
    );

    // The app's own database, exactly as an app would have it: opened by the
    // app, and handed to Code Scout as a live connection.
    shop = await databaseFactory.openDatabase('${scratch.path}/shop.db');
    await shop.execute('CREATE TABLE flags ('
        'id INTEGER PRIMARY KEY, name TEXT NOT NULL, value TEXT NOT NULL)');
    await shop.insert('flags', {'name': 'checkout_v2', 'value': _flagWas});
    await shop.insert('flags', {'name': 'dark_mode', 'value': 'on'});

    // `v` has no declared type, so it has no affinity and SQLite converts
    // nothing before comparing. That is what makes it the one place a scalar
    // arriving as the wrong JSON type actually shows up. See the test below.
    await shop.execute('CREATE TABLE settings (k TEXT, v)');
    await shop.insert('settings', {'k': 'rollout', 'v': 25});

    CodeScout.instance.registerDatabase('shop.db', CodeScoutSqflite(shop),
        writable: true);

    // A second source, of the other kind, registered read only. Two things at
    // once: the key-value shape crosses the wire, and there is something for
    // the write gate to refuse.
    CodeScout.instance.registerDatabase(
      'prefs',
      CodeScoutKeyValue(
        keys: () async => prefs.keys,
        readKey: (k) async => prefs[k],
        writeKey: (k, v) async => prefs[k] = v,
      ),
    );

    final code = await dash.mintPairingCode();
    final paired = await CodeScout.instance.startLiveSession(code);
    expect(paired, isTrue,
        reason: 'the SDK could not pair with $env: '
            '${LiveSessionClient.i.error}');

    sessionID = LiveSessionClient.i.sessionId!;
  });

  tearDownAll(() async {
    await CodeScout.instance.stopLiveSession();
    await CodeScout.instance.dispose();
    await shop.close();
  });

  test('the dashboard is offered exactly what the app registered', () async {
    final res = await dash.project('live/$sessionID/db');
    expect(res.status, 200);

    expect(res.body, contains('shop.db'));
    expect(res.body, contains('prefs'));
    // The table came from sqlite_master on the device, not from anything this
    // test told the server.
    expect(res.body, contains('data-db-table="flags"'),
        reason: 'the schema rail has no table from the device: ${res.body}');

    // The SDK's own log store lives in the same directory and is not offered,
    // because nothing registered it. That is the whole security model.
    expect(res.body, isNot(contains('code_scout.db')));
  });

  test('a page of rows is the app-s own data', () async {
    final res = await rows('shop.db', 'flags');
    expect(res.status, 200);

    for (final want in ['checkout_v2', 'dark_mode', 'name', 'value']) {
      expect(res.body, contains(want),
          reason: 'the grid is missing $want: ${res.body}');
    }
  });

  test('a key-value store crosses the wire as a table too', () async {
    final res = await rows('prefs', 'keys');
    expect(res.status, 200);
    expect(res.body, contains('theme'));
    expect(res.body, contains('dark'));
  });

  test('nothing the app did not register can be read', () async {
    final res = await rows('code_scout.db', 'logs');
    // 200 with the refusal in the markup: htmx does not swap the body of a
    // non-2xx response, so an error behind a 404 would never reach the screen.
    expect(res.status, 200);
    expect(res.body, contains('No database is registered'),
        reason: 'an unregistered name was not refused: ${res.body}');
  });

  test('the dashboard changes a cell and the device really writes it',
      () async {
    final res = await save(
      db: 'shop.db',
      table: 'flags',
      column: 'value',
      // The row handle the grid rendered.
      handle: '1',
      was: _flagWas,
      value: _flagNow,
    );
    expect(res.status, 200);
    expect(res.body, isNot(contains('Could not')), reason: res.body);

    // The assertion that matters. Not what the dashboard said, and not what the
    // SDK returned: what is in the app's database now.
    final stored =
        await shop.query('flags', where: 'id = ?', whereArgs: [1]);
    expect(stored.single['value'], _flagNow,
        reason: 'the dashboard reported a save that never reached SQLite');
  });

  // A number has to arrive at the device as a number.
  //
  // The form carries every field as text, and the server turns each one back
  // into the JSON value it came from before sending it on. Where the column has
  // an affinity SQLite would paper over a mistake here, converting '25' to 25
  // before comparing. A column declared with no type has no affinity and
  // converts nothing, so `v IS '25'` against the integer 25 is false and the
  // conflict check refuses a row nobody has touched.
  test('a number goes back to the device as a number', () async {
    final res = await save(
      db: 'shop.db',
      table: 'settings',
      column: 'v',
      handle: '1',
      was: '25',
      value: '50',
    );
    expect(res.status, 200);

    final stored =
        await shop.query('settings', where: 'k = ?', whereArgs: ['rollout']);
    // Stringified, because a column with no declared type keeps whatever it is
    // given and this test is about the edit landing, not about its storage
    // class.
    expect('${stored.single['v']}', '50',
        reason: 'the edit never landed, so the old value did not match the '
            'row it was read from: ${res.body}');
  });

  test('a stale value is refused rather than overwritten', () async {
    // The value on screen is now out of date, which is what happens when the
    // app changed the row while the editor was open.
    final res = await save(
      db: 'shop.db',
      table: 'flags',
      column: 'value',
      handle: '1',
      was: _flagWas,
      value: 'stale-write',
    );
    expect(res.status, 200);

    final stored =
        await shop.query('flags', where: 'id = ?', whereArgs: [1]);
    expect(stored.single['value'], _flagNow,
        reason: 'a save carrying the wrong old value overwrote the row');
  });

  test('a source registered for browsing only refuses to be written', () async {
    final res = await save(
      db: 'prefs',
      table: 'keys',
      column: 'value',
      handle: 'theme',
      was: 'dark',
      value: 'light',
    );
    expect(res.status, 200);
    expect(res.body, contains('registered for browsing only'),
        reason: 'the write gate did not refuse: ${res.body}');
    expect(prefs['theme'], 'dark',
        reason: 'a read-only source was written to anyway');
  });

  test('a successful edit leaves a record in the app-s own logs', () async {
    // The device writes it through the ordinary logging pipeline, so it lands
    // in the session timeline with everything else rather than in an audit
    // table nobody looks at.
    await CodeScout.instance.flush();

    final logs = await dash.exportLogs(query: 'tag:codescout');
    expect(
        logs.map((l) => l['message'] as String),
        contains(allOf(contains('shop.db'), contains('flags.value'),
            contains(dashboardEmail))),
        reason: 'no audit line for the edit reached the dashboard: '
            '${logs.map((l) => l['message']).toList()}');
  });
}
