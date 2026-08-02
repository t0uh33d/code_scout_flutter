part of 'config.dart';

/// What to strip before anything is recorded.
///
/// Opt-in: out of the box Code Scout records what your app sends, unchanged.
/// You decide what is sensitive, because you are the one who knows — and
/// because a debugging tool that hides the header you are debugging is not
/// much of a debugging tool.
///
/// [commonHeaders] and [commonBodyKeys] are there so you do not have to type
/// the obvious ones, and [RedactionBehavior.recommended] turns them all on:
///
/// ```dart
/// // Nothing redacted — the default
/// RedactionBehavior()
///
/// // Just the ones you care about
/// RedactionBehavior(headers: {'authorization'}, bodyKeys: {'password'})
///
/// // The common list, plus your own
/// RedactionBehavior.recommended(bodyKeys: {'order_signature'})
///
/// // The common list, minus one you need to see today
/// RedactionBehavior(
///   headers: RedactionBehavior.commonHeaders.difference({'authorization'}),
///   bodyKeys: RedactionBehavior.commonBodyKeys,
/// )
/// ```
///
/// Whatever is redacted is replaced at capture, before the log reaches SQLite,
/// so a redacted value is never written to disk or uploaded.
class RedactionBehavior {
  const RedactionBehavior({
    this.headers = const {},
    this.bodyKeys = const {},
    this.maxBodyBytes = 32 * 1024,
  });

  /// Everything in [commonHeaders] and [commonBodyKeys], plus anything you add.
  factory RedactionBehavior.recommended({
    Set<String> headers = const {},
    Set<String> bodyKeys = const {},
    int maxBodyBytes = 32 * 1024,
  }) {
    return RedactionBehavior(
      headers: {...commonHeaders, ...headers},
      bodyKeys: {...commonBodyKeys, ...bodyKeys},
      maxBodyBytes: maxBodyBytes,
    );
  }

  /// Header names to redact. Matched case-insensitively, because HTTP header
  /// names are.
  final Set<String> headers;

  /// Body and metadata keys to redact, at any depth including inside lists.
  /// Matched ignoring case and separators, so one entry covers `access_token`,
  /// `accessToken` and `Access-Token`.
  final Set<String> bodyKeys;

  /// Bodies larger than this are truncated. Not a privacy setting — a single
  /// response can be megabytes, and uploading that from a phone is a cost the
  /// person holding it pays. Zero disables the cap.
  final int maxBodyBytes;

  /// The credential headers most apps have. Not applied unless you ask for
  /// them, by listing them or using [RedactionBehavior.recommended].
  static const Set<String> commonHeaders = {
    'authorization',
    'proxy-authorization',
    'cookie',
    'set-cookie',
    'x-api-key',
    'api-key',
    'x-auth-token',
    'x-access-token',
    'x-session-token',
    'x-csrf-token',
    'x-xsrf-token',
  };

  /// The body keys most apps have.
  static const Set<String> commonBodyKeys = {
    'password',
    'passwd',
    'pwd',
    'token',
    'access_token',
    'refresh_token',
    'id_token',
    'auth_token',
    'secret',
    'client_secret',
    'api_key',
    'authorization',
    'session_id',
    'credit_card',
    'card_number',
    'cvv',
    'cvc',
    'ssn',
    'pin',
  };

  /// Whether there is anything to do. Empty lists are the off switch — there
  /// is no separate flag to forget to flip.
  bool get enabled => headers.isNotEmpty || bodyKeys.isNotEmpty;

  /// Lower-cased header names, computed once per capture rather than per
  /// header.
  Set<String> get headerNames => headers.map((h) => h.toLowerCase()).toSet();

  /// Normalised body keys, so the set matches however a field is spelled.
  Set<String> get bodyKeyNames => bodyKeys.map(normaliseKey).toSet();

  /// Lower-cases and drops separators, so one entry covers every spelling a
  /// codebase might use for the same field.
  static String normaliseKey(String key) =>
      key.toLowerCase().replaceAll(RegExp(r'[-_\s]'), '');
}
