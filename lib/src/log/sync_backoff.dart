import 'dart:io';

/// The server asked for quiet. Not a failure — an instruction.
///
/// This distinction is the whole point. Before it existed, every non-200 was
/// one untyped throw, five in a row stopped the sync worker for the rest of the
/// process, and the only thing that could restart it was `init()`. A server
/// correctly saying "you are over your allowance, come back after midnight"
/// would therefore have permanently stopped logging.
class SyncBackoff implements Exception {
  const SyncBackoff(this.retryAfter);

  final Duration retryAfter;

  @override
  String toString() => 'SyncBackoff(${retryAfter.inSeconds}s)';
}

/// The batch was too large for the server to accept. Also not a failure: the
/// answer is to send less, not to give up.
class UploadTooLarge implements Exception {
  const UploadTooLarge();

  @override
  String toString() => 'UploadTooLarge()';
}

/// The floor. A server answering "retry in 0 seconds" would be a busy loop.
const Duration minBackoff = Duration(seconds: 1);

/// The ceiling. A daily cap legitimately means "come back tomorrow", but
/// nothing may park the worker longer than that — a hostile or misconfigured
/// intermediary must not be able to silence an SDK indefinitely.
const Duration maxBackoff = Duration(hours: 24);

/// Reads a Retry-After header.
///
/// RFC 9110 allows both delta-seconds and an HTTP date, and proxies emit both.
/// The date form is parsed against the device clock, which is routinely wrong,
/// so anything it produces is clamped like everything else.
///
/// Anything missing or unreadable falls back to [fallback] rather than to zero:
/// a header we cannot parse means "wait", not "retry immediately".
Duration parseRetryAfter(String? header, {required Duration fallback}) {
  final raw = header?.trim();
  if (raw == null || raw.isEmpty) return _clamp(fallback);

  final seconds = int.tryParse(raw);
  if (seconds != null) return _clamp(Duration(seconds: seconds));

  try {
    final at = HttpDate.parse(raw);
    return _clamp(at.difference(DateTime.now()));
  } catch (_) {
    return _clamp(fallback);
  }
}

Duration _clamp(Duration d) {
  if (d < minBackoff) return minBackoff;
  if (d > maxBackoff) return maxBackoff;
  return d;
}
