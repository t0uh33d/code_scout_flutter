import 'package:code_scout/src/log/sync_backoff.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 429 is the server working correctly. Before this existed every non-200
/// was one untyped throw, five in a row stopped the worker for the rest of the
/// process, and only a restart could revive it — so a server saying "come back
/// after midnight" permanently stopped logging.
void main() {
  const fallback = Duration(minutes: 10);

  test('delta-seconds is read as seconds', () {
    expect(parseRetryAfter('120', fallback: fallback), const Duration(seconds: 120));
    expect(parseRetryAfter('  120  ', fallback: fallback), const Duration(seconds: 120));
  });

  // RFC 9110 allows both forms and proxies emit both.
  test('an HTTP date is read as a delay from now', () {
    final at = DateTime.now().toUtc().add(const Duration(minutes: 5));
    final header = _httpDate(at);

    final got = parseRetryAfter(header, fallback: fallback);
    expect(got.inSeconds, closeTo(300, 5));
  });

  // Missing or unreadable means "wait", never "retry immediately" — a header
  // we cannot parse must not turn into a busy loop.
  test('anything unreadable falls back rather than to zero', () {
    for (final header in [null, '', '   ', 'soon', 'not-a-date']) {
      expect(parseRetryAfter(header, fallback: fallback), fallback,
          reason: 'header $header');
    }
  });

  test('a zero or negative delay is floored', () {
    expect(parseRetryAfter('0', fallback: fallback), minBackoff);
    expect(parseRetryAfter('-30', fallback: fallback), minBackoff);
    // A date already in the past, which clock skew produces routinely.
    final past = _httpDate(DateTime.now().toUtc().subtract(const Duration(hours: 1)));
    expect(parseRetryAfter(past, fallback: fallback), minBackoff);
  });

  // A daily cap legitimately means "tomorrow", but nothing may park the worker
  // longer than a day — a hostile or misconfigured proxy must not be able to
  // silence an SDK for a week.
  test('an absurd delay is capped at a day', () {
    expect(parseRetryAfter('99999999', fallback: fallback), maxBackoff);
    final farFuture = _httpDate(DateTime.now().toUtc().add(const Duration(days: 400)));
    expect(parseRetryAfter(farFuture, fallback: fallback), maxBackoff);
  });

  test('the fallback is clamped too', () {
    expect(parseRetryAfter(null, fallback: const Duration(days: 30)), maxBackoff);
    expect(parseRetryAfter(null, fallback: Duration.zero), minBackoff);
  });

  test('the two instructions are distinguishable from a failure', () {
    expect(const SyncBackoff(Duration(seconds: 5)), isA<Exception>());
    expect(const UploadTooLarge(), isA<Exception>());
    expect(const SyncBackoff(Duration(seconds: 5)).retryAfter,
        const Duration(seconds: 5));
  });
}

String _httpDate(DateTime utc) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${days[utc.weekday - 1]}, ${two(utc.day)} ${months[utc.month - 1]} '
      '${utc.year} ${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)} GMT';
}
