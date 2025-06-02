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

  // String _hashSecret(String secret) {
  //   final hmac = Hmac(sha256, utf8.encode(projectID));
  //   return hex.encode(hmac.convert(utf8.encode(secret)).bytes);
  // }

  bool? _credsValid;

  Future<bool> validateCredentials() async {
    if (_credsValid != null) return _credsValid!;

    try {
      Uri uri = Uri.parse('$link/api/validate');
      final response = await http.get(uri, headers: authHeaders);
      if (response.statusCode == 200) {
        _credsValid = true;
      } else {
        _credsValid = false;
      }
    } catch (e) {
      _credsValid = false;
    }

    return _credsValid!;
  }
}
