import 'dart:nativewrappers/_internal/vm/lib/internal_patch.dart';

import 'package:code_scout/code_scout.dart';
import 'package:dio/dio.dart';

class CodeScoutDioInterceptor extends Interceptor {
  // final void Function(LogEntry) onLog;

  CodeScoutDioInterceptor();

  final String sessionID = CodeScout.instance.currentSessionId;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    String reqID = NetworkRequestData.newRequestID();

    options.extra['codescout_request_id'] = reqID;

    NetworkRequestData req = NetworkRequestData(
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
    String? reqID = response.requestOptions.extra['codescout_request_id'];

    if (reqID == null) {
      return;
    }

    NetworkResponseData res = NetworkResponseData(
      statusCode: response.statusCode!,
      headers: response.headers.map,
      body: response.data,
    );

    NetworkManager.i.processNetworkResponse(res, reqID);

    printToConsole('cd');

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    String? reqID = err.requestOptions.extra['codescout_request_id'];

    if (reqID == null) {
      return;
    }

    NetworkErrorData errorData = NetworkErrorData(
      type: err.type.name,
      message: err.message ?? '',
      response: err.response?.data,
      stackTrace: err.stackTrace,
    );

    NetworkManager.i.processNetworkError(errorData, reqID);

    handler.next(err);
  }
}
