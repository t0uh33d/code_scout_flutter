import 'dart:convert';
import 'dart:typed_data';

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

    // Capture must never fail the request it observes.
    try {
      NetworkManager.i.processNetworkRequest(_createRequestData(request, reqID));
    } catch (_) {}

    final http.StreamedResponse response;
    try {
      response = await _innerClient.send(request);
    } catch (e, stackTrace) {
      try {
        _processError(e, stackTrace, reqID);
      } catch (_) {}
      rethrow;
    }

    // The body stream is single-subscription: reading it here would hand the
    // caller an already-drained stream. Buffer it, log from the buffer, and
    // return an equivalent response backed by the buffered bytes.
    // ponytail: buffers whole bodies in memory; add a size cap + capture
    // opt-out if large downloads become a real use case.
    final bytes = await response.stream.toBytes();

    try {
      _processResponse(response, bytes, reqID);
    } catch (_) {}

    return http.StreamedResponse(
      http.ByteStream.fromBytes(bytes),
      response.statusCode,
      contentLength: bytes.length,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
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

  void _processResponse(
    http.StreamedResponse response,
    Uint8List bytes,
    String reqID,
  ) {
    NetworkManager.i.processNetworkResponse(
      NetworkResponseData(
        statusCode: response.statusCode,
        headers: response.headers,
        body: utf8.decode(bytes, allowMalformed: true),
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
