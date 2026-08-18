part of 'config.dart';

/// How a credential check went, in the four ways it can go wrong plus the one
/// way it can go right.
///
/// Every one of these used to be the same `false`, which is why the overlay
/// could report "invalid credentials" for a server that was never running.
/// Telling them apart is what lets Info name the fix instead of the symptom.
enum ConnectionOutcome {
  /// Nothing has asked yet.
  unchecked,

  /// No credentials configured. Local mode, which is a supported way to use
  /// this rather than a failure.
  unconfigured,

  /// Nothing answered: connection refused, DNS, TLS, or a timeout. On a
  /// physical device this is usually `localhost`, which is the phone.
  unreachable,

  /// Something answered and turned the credentials down.
  rejected,

  /// Something answered, but there is no CodeScout at that address.
  notFound,

  /// Reached, answered, and not one of the above.
  refused,

  ok;

  bool get isOk => this == ConnectionOutcome.ok;
}

class ProjectCredentials {
  final String projectID;
  final String projectSecret;
  final String link;

  ProjectCredentials({
    required this.projectID,
    required this.projectSecret,
    required this.link,
  }) {
    if (projectID.isEmpty || projectSecret.isEmpty) {
      throw ArgumentError('Project key and secret cannot be empty.');
    }

    // isAbsolute alone is not enough, and the way it falls short is quiet.
    // `localhost:24275/` is an absolute URI as far as Dart is concerned — it
    // reads `localhost` as the scheme and leaves the host empty — so it passed
    // this check and then failed much later, inside the catch in
    // validateCredentials, as "your credentials are invalid". Requiring a host
    // and a scheme we can actually open says so here, where the mistake is.
    final uri = Uri.tryParse(link);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw ArgumentError.value(link, 'link',
          'must be an http or https URL with a host, like http://localhost:24275/');
    }

    if (!link.endsWith('/')) {
      throw ArgumentError('Link must end with a trailing slash.');
    }
  }

  Future<bool> get valid async => await validateCredentials();

  /// How the last check went.
  ///
  /// Every failure used to collapse into one `false`, so the SDK could not tell
  /// a server that was never running from a secret that was rejected — and the
  /// overlay reported "invalid credentials" for a connection refused, which
  /// sends people looking in the wrong place.
  ConnectionOutcome _outcome = ConnectionOutcome.unchecked;

  ConnectionOutcome get outcome => _outcome;

  /// What the server called the project, when it answered. The dashboard
  /// already returns it from `/api/validate`; the SDK used to read the sample
  /// rate out of that reply and throw the rest away. "Connected" answers
  /// nothing if you are pointed at the wrong project.
  String? _projectName;

  String? get projectName => _projectName;

  /// The detail behind a failure, in words meant for a person.
  String? _detail;

  String? get detail => _detail;

  /// Runs the check again from scratch, for a Test connection button. The
  /// cached [validateCredentials] is right for startup and wrong for a control
  /// whose whole purpose is to re-ask after you changed something.
  Future<ConnectionOutcome> check() async {
    _credsValid = null;
    await validateCredentials();
    return _outcome;
  }

  Map<String, String> get authHeaders {
    final headers = {GlobalVars.pcKey: projectID};
    headers[GlobalVars.pcSecret] = projectSecret;
    return headers;
  }

  bool? _credsValid;

  /// The project's session sampling rate as the server reports it, or null if
  /// it has not been asked yet, could not be reached, or said nothing useful.
  /// Null means "no opinion" and leaves the app's own rate alone.
  double? _serverSampleRate;

  double? get serverSampleRate => _serverSampleRate;

  Future<bool> validateCredentials() async {
    if (_credsValid != null) return _credsValid!;

    final client = HttpClient();
    try {
      final uri = Uri.parse('${link}api/validate');
      final request = await client.getUrl(uri);
      authHeaders.forEach((k, v) => request.headers.set(k, v));
      final response = await request.close();
      _credsValid = response.statusCode == 200;

      if (_credsValid!) {
        final body = await response.transform(utf8.decoder).join();
        _serverSampleRate = _readSampleRate(body);
        _projectName = _readProjectName(body);
        _outcome = ConnectionOutcome.ok;
        _detail = null;
      } else {
        // Drain it regardless, or the socket is never returned to the pool.
        await response.drain<void>();
        _outcome = switch (response.statusCode) {
          401 || 403 => ConnectionOutcome.rejected,
          // Reached a server, but there is no CodeScout at that address.
          // Usually a dashboard URL pasted with a path on the end.
          404 => ConnectionOutcome.notFound,
          _ => ConnectionOutcome.refused,
        };
        _detail = 'The server answered ${response.statusCode}.';
      }
    } on SocketException catch (e) {
      _credsValid = false;
      _outcome = ConnectionOutcome.unreachable;
      _detail = e.osError?.message ?? e.message;
    } on HandshakeException catch (e) {
      _credsValid = false;
      _outcome = ConnectionOutcome.unreachable;
      _detail = e.message;
    } on TimeoutException {
      _credsValid = false;
      _outcome = ConnectionOutcome.unreachable;
      _detail = 'The server did not answer in time.';
    } catch (e) {
      _credsValid = false;
      _outcome = ConnectionOutcome.unreachable;
      _detail = e.toString();
    } finally {
      client.close();
    }

    return _credsValid!;
  }

  /// The project's name, or null for anything unrecognised. Like
  /// [_readSampleRate], nothing here may throw: a stray proxy page must cost
  /// this SDK a label, not the app's logging.
  static String? _readProjectName(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final name = decoded['name'];
      return name is String && name.isNotEmpty ? name : null;
    } catch (_) {
      return null;
    }
  }

  /// Reads the rate out of the validate response, and returns null for
  /// anything it does not recognise.
  ///
  /// Nothing here may throw. A server that answers with a stray proxy page
  /// must cost this SDK its remote setting, not the app's logging.
  static double? _readSampleRate(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final rate = decoded['session_sample_rate'];
      return rate is num ? rate.toDouble() : null;
    } catch (_) {
      return null;
    }
  }
}
