part of 'config.dart';

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
        _serverSampleRate = _readSampleRate(
          await response.transform(utf8.decoder).join(),
        );
      } else {
        // Drain it regardless, or the socket is never returned to the pool.
        await response.drain<void>();
      }
    } catch (e) {
      _credsValid = false;
    } finally {
      client.close();
    }

    return _credsValid!;
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
