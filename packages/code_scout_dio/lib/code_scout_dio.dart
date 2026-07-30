import 'package:code_scout/code_scout.dart';
import 'package:dio/dio.dart';

export 'package:code_scout/code_scout.dart' show NetworkManager;

/// A Dio [Interceptor] that automatically captures network requests, responses,
/// and errors for Code Scout.
///
/// ```dart
/// final dio = Dio();
/// dio.interceptors.add(CodeScoutDioInterceptor());
/// ```
class CodeScoutDioInterceptor extends Interceptor {
  CodeScoutDioInterceptor();

  // Capture must never fail the request it observes: every hook does its
  // Code Scout work inside a try/catch and always forwards via handler.next.

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    try {
      final reqID = NetworkRequestData.newRequestID();
      options.extra['codescout_request_id'] = reqID;

      NetworkManager.i.processNetworkRequest(NetworkRequestData(
        method: options.method,
        url: options.uri,
        headers: options.headers,
        body: options.data,
        requestID: reqID,
      ));
    } catch (_) {}
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    try {
      final reqID = response.requestOptions.extra['codescout_request_id'];
      final statusCode = response.statusCode;
      if (reqID != null && statusCode != null) {
        NetworkManager.i.processNetworkResponse(
          NetworkResponseData(
            statusCode: statusCode,
            headers: response.headers.map,
            body: response.data,
          ),
          reqID,
        );
      }
    } catch (_) {}
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    try {
      final reqID = err.requestOptions.extra['codescout_request_id'];
      if (reqID != null) {
        NetworkManager.i.processNetworkError(
          NetworkErrorData(
            type: err.type.name,
            message: err.message ?? '',
            response: err.response?.data,
            stackTrace: err.stackTrace,
          ),
          reqID,
        );
      }
    } catch (_) {}
    handler.next(err);
  }
}
