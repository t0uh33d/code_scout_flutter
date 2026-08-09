// The dashboard's side of an end-to-end test.
//
// The SDK talks to /api/* with project headers, and that is all it ever needs.
// A test also has to act as the person at the dashboard: make a project, read
// the logs back, mint a pairing code, ask a paired device for its tables. All
// of that is behind the web session, so this signs in the way the login form
// does and keeps the cookie.
//
// Shared by every file in test/e2e/, which is why it is here rather than
// private to one of them.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// The account every e2e file signs in as.
///
/// One account, deliberately. Registration only happens on a fresh instance:
/// the first POST creates the super admin and every later one is an ordinary
/// login, so a second email would have nobody to log in as.
const dashboardEmail = 'sdk-e2e@test.local';
const dashboardPassword = 'sdk-e2e-password-123';

class Dashboard {
  Dashboard(String base) : base = base.endsWith('/') ? base : '$base/';

  /// Reads CS_E2E_BASE, or null when there is no server to talk to and the
  /// suite should skip.
  static String? get baseFromEnvironment => Platform.environment['CS_E2E_BASE'];

  final String base;
  String _cookie = '';
  late String projectID;
  late String projectSecret;

  Future<void> signIn() async {
    // Two e2e files run at once and both may find an empty users table, so both
    // try to register and one loses on the unique index. Losing that race means
    // the account now exists, which is exactly what the retry needs.
    for (var attempt = 0; attempt < 3; attempt++) {
      final res = await send('POST', 'api/auth/submit',
          contentType: 'application/x-www-form-urlencoded',
          body: 'name=SDK+E2E'
              '&email=${Uri.encodeQueryComponent(dashboardEmail)}'
              '&password=${Uri.encodeQueryComponent(dashboardPassword)}'
              '&confirm_password=${Uri.encodeQueryComponent(dashboardPassword)}');

      final cookie = res.cookies.where((c) => c.name == 'cs_session');
      if (cookie.isNotEmpty) {
        _cookie = 'cs_session=${cookie.first.value}';
        return;
      }
      if (attempt == 2) {
        throw StateError('sign in failed (${res.status}): no session cookie');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> createProject(String name) async {
    final res = await send('POST', 'api/project',
        contentType: 'application/json',
        body: jsonEncode({'name': name, 'description': 'SDK e2e'}));
    if (res.status != 200) {
      throw StateError('create project failed (${res.status}): ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    projectID = json['id'] as String;
    // The one and only moment the plaintext secret is returned, which is
    // exactly what an SDK needs and why the wizard shows it once.
    projectSecret = json['secret_key'] as String;
  }

  /// The logs the dashboard holds for this project, newest first.
  ///
  /// The export endpoint rather than the log viewer: it answers with the stored
  /// rows as JSON, so an assertion is about the data and not about markup.
  Future<List<Map<String, dynamic>>> exportLogs({String query = ''}) async {
    final res = await send('GET',
        'export/logs?project_id=$projectID&fmt=json&q=${Uri.encodeQueryComponent(query)}');
    if (res.status != 200) {
      throw StateError('export failed (${res.status}): ${res.body}');
    }
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  /// Mints a pairing code and reads it off the fragment the button would have
  /// swapped in.
  ///
  /// Scraping is the honest thing here. The code exists to be read off a screen
  /// and typed into a phone, and there is no API that hands it over, because an
  /// unclaimed code is a credential and only the person who minted it may see
  /// it.
  Future<String> mintPairingCode() async {
    final res = await send('POST', 'project/$projectID/live/new');
    if (res.status != 200) {
      throw StateError('minting a code failed (${res.status}): ${res.body}');
    }
    final match =
        RegExp(r'data-pairing-code[^>]*>([A-Z0-9]+)<').firstMatch(res.body);
    if (match == null) {
      throw StateError('no pairing code in the response: ${res.body}');
    }
    return match.group(1)!;
  }

  /// A GET against a project-scoped page or fragment.
  Future<Res> project(String path) =>
      send('GET', 'project/$projectID/$path');

  /// A form POST against a project-scoped route, which is what every button on
  /// the dashboard does.
  Future<Res> projectForm(String path, Map<String, String> fields) => send(
        'POST',
        'project/$projectID/$path',
        contentType: 'application/x-www-form-urlencoded',
        body: fields.entries
            .map((e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
            .join('&'),
      );

  Future<Res> send(String method, String path,
      {String? body, String? contentType}) async {
    final client = HttpClient();
    try {
      final req = await client.openUrl(method, Uri.parse('$base$path'));
      // Sign in answers 303 and sets the cookie on that response. Following the
      // redirect would hand back the dashboard's headers instead, with no
      // Set-Cookie on them.
      req.followRedirects = false;
      if (_cookie.isNotEmpty) req.headers.set('Cookie', _cookie);
      if (contentType != null) req.headers.set('Content-Type', contentType);
      if (body != null) req.write(body);

      final res = await req.close();
      return Res(res.statusCode, await res.transform(utf8.decoder).join(),
          res.cookies);
    } finally {
      client.close();
    }
  }
}

class Res {
  Res(this.status, this.body, this.cookies);

  final int status;
  final String body;
  final List<Cookie> cookies;
}

/// Points the SDK's temporary directory at a real one.
///
/// `getTemporaryDirectory()` is a platform channel with nothing behind it in a
/// host test. Left unanswered, the compressor throws inside the sync worker's
/// own catch, which reports through `dart:developer`: the upload silently never
/// happens and the failure never prints.
void installScratchPaths(String path) {
  PathProviderPlatform.instance = _ScratchPaths(path);
}

class _ScratchPaths extends PathProviderPlatform {
  _ScratchPaths(this.path);

  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;
}
