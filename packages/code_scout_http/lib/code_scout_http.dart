import 'package:code_scout/code_scout.dart';
import 'package:http/http.dart' as http;

export 'package:code_scout/code_scout.dart' show NetworkManager;

/// An [http.BaseClient] wrapper that automatically captures network requests,
/// responses, and errors for Code Scout.
///
/// ```dart
/// final client = CodeScoutHttpClient(client: http.Client());
/// final response = await client.get(Uri.parse('https://api.example.com/data'));
/// ```
class CodeScoutHttpClient extends http.BaseClient {
  final http.Client _innerClient;

  CodeScoutHttpClient({http.Client? client})
      : _innerClient = client ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final reqID = NetworkRequestData.newRequestID();
    final requestData = _createRequestData(request, reqID);

    NetworkManager.i.processNetworkRequest(requestData);

    try {
      final response = await _innerClient.send(request);
      await _processResponse(response, reqID);
      return response;
    } catch (e, stackTrace) {
      _processError(e, stackTrace, reqID);
      rethrow;
    }
  }

  NetworkRequestData _createRequestData(
    http.BaseRequest request,
    String reqID,
  ) {
    return NetworkRequestData(
      method: request.method,
      url: request.url,
      headers: request.headers,
      body: _readRequestBody(request),
      requestID: reqID,
    );
  }

  String _readRequestBody(http.BaseRequest request) {
    if (request is http.Request) {
      return request.body;
    }
    if (request is http.MultipartRequest) {
      return '[multipart]';
    }
    return '[streamed-body]';
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
