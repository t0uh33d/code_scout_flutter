import 'package:code_scout_http/code_scout_http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  _closeTests();

  // Regression tests for the two 1.0.0 release-breaking bugs:
  // 1. The wrapper returned an already-drained body stream, so every read of
  //    the response threw "Stream has already been listened to".
  // 2. Capture before CodeScout.instance.init() threw LateInitializationError
  //    into the caller's request. Note init() is deliberately NOT called here.
  test('caller can read the response body and capture never fails the request',
      () async {
    final client = CodeScoutHttpClient(
      client: MockClient(
        (request) async => http.Response('{"ok":true}', 200),
      ),
    );

    final res = await client.get(Uri.parse('https://example.com/data'));

    expect(res.statusCode, 200);
    expect(res.body, '{"ok":true}');
  });

  test('errors from the inner client are rethrown untouched', () async {
    final client = CodeScoutHttpClient(
      client: MockClient((request) async => throw http.ClientException('boom')),
    );

    expect(
      () => client.get(Uri.parse('https://example.com/data')),
      throwsA(isA<http.ClientException>()),
    );
  });
}

/// Closing the wrapper has to close what it wraps.
///
/// `BaseClient.close()` is a no-op, so a caller doing the documented thing —
/// a client per unit of work, closed in a finally — kept every pooled socket
/// the inner client held. Wrapping a client silently changed what closing it
/// meant.
class _ClosableSpy extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(const Stream.empty(), 200);

  @override
  void close() => closed = true;
}

void _closeTests() {
  test('close() closes the wrapped client', () {
    final inner = _ClosableSpy();

    CodeScoutHttpClient(client: inner).close();

    expect(inner.closed, isTrue,
        reason: 'the inner client kept its whole connection pool');
  });
}
