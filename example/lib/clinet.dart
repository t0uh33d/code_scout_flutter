import 'package:code_scout/code_scout.dart';
import 'package:http/http.dart' as http;

class CodeScoutHttpClient extends http.BaseClient {
  final http.Client _innerClient;
  final String sessionID = CodeScout.instance.currentSessionId;

  CodeScoutHttpClient({http.Client? client})
    : _innerClient = client ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final reqID = NetworkRequestData.newRequestID();
    final requestData = await _createRequestData(request, reqID);

    NetworkManager.i.processNetworkRequest(requestData);

    try {
      final response = await _innerClient.send(request);
      await _processResponse(response, reqID);
      return response;
    } catch (e, stackTrace) {
      _processError(e, stackTrace, reqID, request);
      rethrow;
    }
  }

  Future<NetworkRequestData> _createRequestData(
    http.BaseRequest request,
    String reqID,
  ) async {
    return NetworkRequestData(
      method: request.method,
      url: request.url,
      headers: request.headers,
      body: await _readRequestBody(request),
      requestID: reqID,
    );
  }

  Future<String> _readRequestBody(http.BaseRequest request) async {
    if (request is http.Request) {
      return request.body;
    }
    if (request is http.MultipartRequest) {
      return "[multipart]";
    }
    return "[streamed-body]";
  }

  Future<void> _processResponse(
    http.StreamedResponse response,
    String reqID,
  ) async {
    final responseBody = await response.stream.bytesToString();

    NetworkManager.i.processNetworkResponse(
      NetworkResponseData(
        statusCode: response.statusCode,
        headers: response.headers,
        body: responseBody,
      ),
      reqID,
    );
  }

  void _processError(
    dynamic error,
    StackTrace stackTrace,
    String reqID,
    http.BaseRequest request,
  ) {
    NetworkManager.i.processNetworkError(
      NetworkErrorData(
        type: error.runtimeType.toString(),
        message: error.toString(),
        stackTrace: stackTrace,
        response: null,
      ),
      reqID,
    );
  }
}
