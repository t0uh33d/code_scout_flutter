part of 'config.dart';

/// What never leaves the device.
///
/// On by default, and deliberately so: a logging SDK that ships `Authorization`
/// headers to a server is building someone else a database of their users'
/// bearer tokens. Redaction happens at capture, before anything is written to
/// SQLite, so the secret is not on disk either.
class RedactionBehavior {
  const RedactionBehavior({
    this.enabled = true,
    this.additionalHeaders = const {},
    this.additionalBodyKeys = const {},
    this.maxBodyBytes = 32 * 1024,
  });

  /// Everything through, redacting nothing. Only sensible when you control
  /// every endpoint the app talks to and the server is your own.
  const RedactionBehavior.off()
      : enabled = false,
        additionalHeaders = const {},
        additionalBodyKeys = const {},
        maxBodyBytes = 0;

  final bool enabled;

  /// Header names to redact on top of [defaultHeaders].
  final Set<String> additionalHeaders;

  /// Body and metadata keys to redact on top of [defaultBodyKeys].
  final Set<String> additionalBodyKeys;

  /// Bodies larger than this are truncated. A single response can be megabytes,
  /// and shipping that to a log server on a mobile connection is a cost the
  /// person holding the phone pays. Zero disables the cap.
  final int maxBodyBytes;

  /// The headers that carry credentials. Anything here is replaced wholesale —
  /// there is no such thing as a partly sensitive Authorization header.
  static const Set<String> defaultHeaders = {
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

  /// Body keys that usually hold a secret. Matched on a normalised name, so
  /// `access_token`, `accessToken` and `Access-Token` are all the same key.
  static const Set<String> defaultBodyKeys = {
    'password',
    'passwd',
    'pwd',
    'token',
    'accesstoken',
    'refreshtoken',
    'idtoken',
    'authtoken',
    'secret',
    'clientsecret',
    'apikey',
    'authorization',
    'sessionid',
    'creditcard',
    'cardnumber',
    'cvv',
    'cvc',
    'ssn',
    'pin',
  };

  Set<String> get headers => {
        ...defaultHeaders,
        ...additionalHeaders.map((h) => h.toLowerCase()),
      };

  Set<String> get bodyKeys => {
        ...defaultBodyKeys,
        ...additionalBodyKeys.map(normaliseKey),
      };

  /// Lower-cases and drops separators, so one entry covers every spelling a
  /// codebase might use for the same field.
  static String normaliseKey(String key) =>
      key.toLowerCase().replaceAll(RegExp(r'[-_\s]'), '');
}
