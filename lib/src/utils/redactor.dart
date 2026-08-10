import 'dart:convert';

import 'package:code_scout/code_scout.dart';

/// Applies [RedactionBehavior] to what the SDK is about to record.
///
/// Redaction is opt-in: with nothing configured this is a pass-through, and
/// what your app sent is what gets recorded. Whatever you do configure is
/// applied at capture, before the log reaches SQLite, so a redacted value is
/// not on disk and was never in a batch.
class Redactor {
  const Redactor._();

  /// What a redacted value is replaced with. The dashboard recognises this
  /// exact string and renders it as a redaction rather than as content.
  static const String placeholder = '[redacted]';

  static RedactionBehavior get _config =>
      CodeScout.instance.configuration.redaction;

  /// Headers, matched on the header name case-insensitively. HTTP header names
  /// are case-insensitive, and a server that answers `Set-Cookie` is the same
  /// server that answers `set-cookie`.
  static Map<String, dynamic>? headers(Object? raw, [RedactionBehavior? config]) {
    final cfg = config ?? _config;
    if (raw is! Map) return raw is Map<String, dynamic> ? raw : null;

    // Resolved once, not once per header: the getter builds a new set.
    final redact = cfg.headerNames;

    final out = <String, dynamic>{};
    raw.forEach((key, value) {
      final name = key.toString();
      out[name] = redact.contains(name.toLowerCase()) ? placeholder : value;
    });
    return out;
  }

  /// A body, or any other structure worth walking: nested maps and lists are
  /// followed, because `{"user": {"password": "..."}}` is the common shape and
  /// only looking at the top level would miss it.
  static Object? body(Object? raw, [RedactionBehavior? config]) {
    final cfg = config ?? _config;
    final redacted = cfg.bodyKeys.isEmpty ? raw : _walk(raw, cfg.bodyKeyNames);
    // The cap applies either way: it is about upload size, not about secrets.
    return _cap(redacted, cfg);
  }

  /// Log metadata gets the same treatment as a body. A developer logging
  /// `metadata: {'token': ...}` has the same problem as one whose request body
  /// carries it, and it is the same walk.
  static Map<String, dynamic>? metadata(Map<String, dynamic>? raw,
      [RedactionBehavior? config]) {
    final cfg = config ?? _config;
    if (raw == null || cfg.bodyKeys.isEmpty) return raw;
    final walked = _walk(raw, cfg.bodyKeyNames);
    return walked is Map<String, dynamic> ? walked : raw;
  }

  /// True when the redaction config names this key, matched the same way body
  /// keys are: case- and separator-insensitively, so `auth_token`, `authToken`
  /// and `Auth-Token` are one name.
  ///
  /// Used for database column names, which are exactly the same problem as body
  /// keys and deserve exactly the same answer rather than a second matcher that
  /// drifts from this one.
  static bool hides(String name, [RedactionBehavior? config]) {
    final cfg = config ?? _config;
    if (cfg.bodyKeys.isEmpty) return false;
    return cfg.bodyKeyNames.contains(RedactionBehavior.normaliseKey(name));
  }

  static Object? _walk(Object? value, Set<String> redact) {
    if (value is Map) {
      final out = <String, dynamic>{};
      value.forEach((key, child) {
        final name = key.toString();
        out[name] = redact.contains(RedactionBehavior.normaliseKey(name))
            ? placeholder
            : _walk(child, redact);
      });
      return out;
    }
    if (value is List) {
      return value.map((child) => _walk(child, redact)).toList();
    }
    return value;
  }

  /// Truncates an oversized body.
  ///
  /// The result is a string rather than a shortened structure: half a JSON
  /// document is not JSON, and a reader is better served by real text plus an
  /// honest note about what was dropped.
  static Object? _cap(Object? value, RedactionBehavior cfg) {
    if (value == null || cfg.maxBodyBytes <= 0) return value;

    final encoded = value is String ? value : _encode(value);
    if (encoded == null) return value;

    final bytes = utf8.encode(encoded);
    if (bytes.length <= cfg.maxBodyBytes) return value;

    // Cut on a character boundary, not a byte one, or the tail is mojibake.
    final kept = utf8.decode(bytes.sublist(0, cfg.maxBodyBytes), allowMalformed: true);
    return '$kept\n\n... truncated by Code Scout. The whole body was ${formatSize(bytes.length)}.';
  }

  static String? _encode(Object? value) {
    try {
      return jsonEncode(value);
    } catch (_) {
      // Something that will not encode is left alone rather than mangled.
      return null;
    }
  }

  /// Bytes as a person reads them: "42.1 KB". Shared with the database browser
  /// so a blob and a truncated body are sized the same way.
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
