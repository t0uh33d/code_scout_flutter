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

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final reqID = NetworkRequestData.newRequestID();
    options.extra['codescout_request_id'] = reqID;

    final req = NetworkRequestData(
      method: options.method,
      url: options.uri,
      headers: options.headers,
      body: options.data,
      requestID: reqID,
    );

    NetworkManager.i.processNetworkRequest(req);
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final reqID = response.requestOptions.extra['codescout_request_id'];
    if (reqID == null) {
      handler.next(response);
      return;
    }

    final res = NetworkResponseData(
      statusCode: response.statusCode!,
      headers: response.headers.map,
      body: response.data,
    );

    NetworkManager.i.processNetworkResponse(res, reqID);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final reqID = err.requestOptions.extra['codescout_request_id'];
    if (reqID == null) {
      handler.next(err);
      return;
    }

    final errorData = NetworkErrorData(
      type: err.type.name,
      message: err.message ?? '',
      response: err.response?.data,
      stackTrace: err.stackTrace,
    );

    NetworkManager.i.processNetworkError(errorData, reqID);
    handler.next(err);
  }
}
