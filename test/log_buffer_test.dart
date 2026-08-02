import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

/// The overlay reads this and nothing else, so what it holds is what someone
/// holding the phone sees.
void main() {
  setUp(LogBuffer.i.clear);
  tearDown(LogBuffer.i.clear);

  LogEntry entry(
    String message, {
    LogLevel level = LogLevel.info,
    Set<String> tags = const {},
    bool network = false,
    String? requestId,
    NetworkCallPhase? phase,
    Map<String, dynamic>? metadata,
  }) {
    return LogEntry(
      level: level,
      message: message,
      sessionID: 'session',
      tags: tags,
      isNetworkCall: network,
      requestId: requestId,
      callPhase: phase,
      metadata: metadata,
    );
  }

  test('newest first, which is the order the overlay lists them', () {
    LogBuffer.i.add(entry('first'));
    LogBuffer.i.add(entry('second'));

    expect(LogBuffer.i.entries.map((e) => e.message), ['second', 'first']);
  });

  // A chatty app must not grow the heap without bound, and the entry that
  // falls off has to be the oldest — losing the newest would drop the one you
  // opened the overlay to look at.
  test('the buffer is capped, and drops the oldest', () {
    for (var i = 0; i < LogBuffer.maxEntries + 20; i++) {
      LogBuffer.i.add(entry('log $i'));
    }

    expect(LogBuffer.i.length, LogBuffer.maxEntries);
    expect(LogBuffer.i.entries.first.message, 'log ${LogBuffer.maxEntries + 19}');
    expect(LogBuffer.i.entries.last.message, 'log 20');
  });

  test('tags are ranked by use, so the chips are the ones worth having', () {
    LogBuffer.i.add(entry('a', tags: {'network', 'checkout'}));
    LogBuffer.i.add(entry('b', tags: {'network'}));
    LogBuffer.i.add(entry('c', tags: {'network'}));
    LogBuffer.i.add(entry('d', tags: {'checkout'}));
    LogBuffer.i.add(entry('e', tags: {'rare'}));

    expect(LogBuffer.i.tags(), ['network', 'checkout', 'rare']);
  });

  test('a log with no tags contributes none', () {
    LogBuffer.i.add(entry('plain'));
    expect(LogBuffer.i.tags(), isEmpty);
  });

  group('network calls', () {
    void seedCall(String id, {int? status, bool error = false}) {
      LogBuffer.i.add(entry(
        'Network Request',
        network: true,
        requestId: id,
        phase: NetworkCallPhase.request,
        metadata: {'method': 'POST', 'url': 'https://api.test/v2/pay'},
      ));
      if (status != null) {
        LogBuffer.i.add(entry(
          'Network Response',
          network: true,
          requestId: id,
          phase: NetworkCallPhase.response,
          metadata: {'status_code': status},
        ));
      }
      if (error) {
        LogBuffer.i.add(entry(
          'Network Error',
          level: LogLevel.error,
          network: true,
          requestId: id,
          phase: NetworkCallPhase.error,
          metadata: {'type': 'DioExceptionType.receiveTimeout'},
        ));
      }
    }

    test('phases pair into one call', () {
      seedCall('req-1', status: 200);
      LogBuffer.i.add(entry('not a network log'));

      final calls = LogBuffer.i.calls();
      expect(calls, hasLength(1));
      expect(calls.first.method, 'POST');
      expect(calls.first.path, '/v2/pay');
      expect(calls.first.statusCode, 200);
      expect(calls.first.status, '200');
      expect(calls.first.failed, isFalse);
    });

    test('a bad status and a transport error both read as failed', () {
      seedCall('req-401', status: 401);
      seedCall('req-boom', error: true);

      final byStatus = {for (final c in LogBuffer.i.calls()) c.status: c};
      expect(byStatus['401']!.failed, isTrue);
      expect(byStatus['error']!.failed, isTrue);
      expect(byStatus['error']!.hasError, isTrue);
    });

    test('a call with only a request is pending, and has no duration', () {
      seedCall('req-pending');

      final call = LogBuffer.i.calls().single;
      expect(call.status, 'pending');
      // Timing an unfinished call against now would grow on every rebuild.
      expect(call.duration, isNull);
    });

    // The request phase falls off the back of the buffer long before the
    // response does on a chatty app. The response nests the request it belongs
    // to, so the row still knows what it called.
    test('a call whose request scrolled away still has a method and path', () {
      LogBuffer.i.add(entry(
        'Network Response',
        network: true,
        requestId: 'req-orphan',
        phase: NetworkCallPhase.response,
        metadata: {
          'status_code': 204,
          'request': {'method': 'DELETE', 'url': 'https://api.test/v2/cart/items/9f21'},
        },
      ));

      final call = LogBuffer.i.calls().single;
      expect(call.method, 'DELETE');
      expect(call.path, '/v2/cart/items/9f21');
      expect(call.hasRequest, isFalse);
    });

    test('a network log with no request id is not a call', () {
      LogBuffer.i.add(entry('Network Request', network: true));
      expect(LogBuffer.i.calls(), isEmpty);
    });
  });

  // The overlay is rebuilt from this, so a listener that never fires is a
  // sheet that stops updating while you watch it.
  test('adding notifies whoever is watching', () {
    var notifications = 0;
    void listener() => notifications++;

    LogBuffer.i.addListener(listener);
    addTearDown(() => LogBuffer.i.removeListener(listener));

    LogBuffer.i.add(entry('one'));
    LogBuffer.i.add(entry('two'));

    expect(notifications, 2);
  });
}
