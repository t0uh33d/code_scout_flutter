import 'package:code_scout_http/code_scout_http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
