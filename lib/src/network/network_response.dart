part of 'network_manager.dart';

class NetworkResponseData extends NetworkData {
  final int statusCode;
  final Map<String, dynamic>? headers;
  final dynamic body;
  final DateTime? timestamp;

  /// The response's size on the wire, when the caller knew it.
  ///
  /// Has to be taken **before** redaction and truncation, which is why it is a
  /// field rather than something measured here: by the time a body reaches
  /// [toMap] the redactor has replaced values with a ten-character marker and
  /// cut anything over 32 KB, so `body.length` would report the size of the
  /// summary rather than of the response.
  final int? byteLength;

  NetworkResponseData({
    required this.statusCode,
    this.headers,
    this.body,
    this.byteLength,
    this.timestamp,
  });

  factory NetworkResponseData.fromMap(Map<String, dynamic> map) {
    return NetworkResponseData(
      statusCode: map['status_code'],
      headers: map['headers'],
      body: map['body'],
      byteLength: map['byte_length'],
      timestamp: DateTime.parse(map['timestamp']),
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'status_code': statusCode,
      'headers': Redactor.headers(headers),
      'body': Redactor.body(body),
      if (byteLength != null) 'byte_length': byteLength,
      'timestamp': timestamp?.toIso8601String(),
      'request': _request?.toMap(),
    };
  }

  NetworkRequestData? _request;

  void attachNetworkRequest(NetworkRequestData request) {
    _request = request;
  }

  @override
  LogEntry generateLogEntry() {
    if (_request == null) {
      throw Exception('Network request not attached');
    }

    _logEntry = LogEntry(
      level: LogLevel.debug,
      message: 'Network Response',
      sessionID: CodeScout.instance.currentSessionId,
      isNetworkCall: true,
      requestId: _request?.requestID,
      callPhase: NetworkCallPhase.response,
      metadata: toMap(),
      tags: {'network'},
    );

    return _logEntry!;
  }
}
