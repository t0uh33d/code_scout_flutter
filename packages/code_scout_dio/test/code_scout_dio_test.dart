import 'dart:typed_data';

import 'package:code_scout_dio/code_scout_dio.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves a canned response without touching the network.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.status = 200, this.body = '{"ok":true}'});

  final int status;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'network down',
    );
  }

  @override
  void close({bool force = false}) {}
}

/// The interceptor runs inside the caller's request chain, so anything it throws
/// fails the HTTP request rather than merely losing a log line. These cover the
/// uninitialized case, which used to throw a LateInitializationError.
void main() {
  Dio dioWith(HttpClientAdapter adapter) => Dio()
    ..httpClientAdapter = adapter
    ..interceptors.add(CodeScoutDioInterceptor());

  test('a request succeeds when CodeScout was never initialized', () async {
    final response = await dioWith(
      _FakeAdapter(),
    ).get<dynamic>('https://example.com/thing');

    expect(response.statusCode, 200);
    expect(response.data, {'ok': true});
  });

  test('an error status still surfaces to the caller', () async {
    expect(
      () => dioWith(
        _FakeAdapter(status: 500, body: '{}'),
      ).get<dynamic>('https://example.com/thing'),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'statusCode',
          500,
        ),
      ),
    );
  });

  test('a transport error propagates unchanged', () async {
    expect(
      () => dioWith(_ThrowingAdapter()).get<dynamic>('https://example.com/x'),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.connectionError,
        ),
      ),
    );
  });

  test('a correlation id is stamped on the request', () async {
    final dio = dioWith(_FakeAdapter());

    final response = await dio.get<dynamic>('https://example.com/thing');

    expect(
      response.requestOptions.extra['codescout_request_id'],
      isA<String>(),
    );
  });
}
