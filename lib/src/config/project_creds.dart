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

    if (!Uri.parse(link).isAbsolute) {
      throw ArgumentError('Link must be a valid absolute URL.');
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

  Future<bool> validateCredentials() async {
    if (_credsValid != null) return _credsValid!;

    final client = HttpClient();
    try {
      final uri = Uri.parse('${link}api/validate');
      final request = await client.getUrl(uri);
      authHeaders.forEach((k, v) => request.headers.set(k, v));
      final response = await request.close();
      _credsValid = response.statusCode == 200;
    } catch (e) {
      _credsValid = false;
    } finally {
      client.close();
    }

    return _credsValid!;
  }
}
