import 'package:code_scout/code_scout.dart';
import 'package:dio/dio.dart';

export 'package:code_scout/code_scout.dart' show NetworkManager;

/// A Dio [Interceptor] that automatically captures network requests, responses,
/// and errors for CodeScout.
///
/// ```dart
/// final dio = Dio();
/// dio.interceptors.add(CodeScoutDioInterceptor());
/// ```
class CodeScoutDioInterceptor extends Interceptor {
  /// Says it is here as soon as it is built, before any call has been made.
  ///
  /// The core cannot detect a package that was never constructed, so an app
  /// that forgot the interceptor shows an empty Network tab that looks exactly
  /// like an app making no calls. Registering at construction is what lets the
  /// overlay tell those two apart.
  CodeScoutDioInterceptor() {
    NetworkManager.i.registerIntegration('dio');
  }

  // Capture must never fail the request it observes: every hook does its
  // CodeScout work inside a try/catch and always forwards via handler.next.

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
            // dio's default validateStatus rejects 4xx and 5xx, so those land
            // here rather than in onResponse. Dropping the code left a dio app
            // unable to tell a 401 from a 504 anywhere.
            statusCode: err.response?.statusCode,
            stackTrace: err.stackTrace,
          ),
          reqID,
        );
      }
    } catch (_) {}
    handler.next(err);
  }
}
