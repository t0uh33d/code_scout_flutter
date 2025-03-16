import 'dart:convert';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

class ProjectCredentials {
  final String projectKey;
  final String projectSecret;

  final String pcKey = "X-Project-Key";
  final String pcSecret = "X-Project-Secret";

  ProjectCredentials({
    required this.projectKey,
    required this.projectSecret,
  }) {
    if (projectKey.isEmpty) {
      throw ArgumentError('Project key cannot be empty');
    }
  }

  Map<String, String> get authHeaders {
    final headers = {pcKey: projectKey};
    if (projectSecret != null) {
      headers[pcSecret] = _hashSecret(projectSecret!);
    }
    return headers;
  }

  String _hashSecret(String secret) {
    // Implement HMAC-based hashing
    final hmac = Hmac(sha256, utf8.encode(projectKey));
    return hex.encode(hmac.convert(utf8.encode(secret)).bytes);
  }
}
