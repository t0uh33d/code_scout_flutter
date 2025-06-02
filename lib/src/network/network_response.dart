part of 'network_manager.dart';

class NetworkResponseData extends NetworkData {
  final int statusCode;
  final Map<String, dynamic>? headers;
  final dynamic body;
  final DateTime? timestamp;

  NetworkResponseData({
    required this.statusCode,
    this.headers,
    this.body,
    this.timestamp,
  });

  factory NetworkResponseData.fromMap(Map<String, dynamic> map) {
    return NetworkResponseData(
      statusCode: map['status_code'],
      headers: map['headers'],
      body: map['body'],
      timestamp: DateTime.parse(map['timestamp']),
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'status_code': statusCode,
      'headers': headers,
      'body': body,
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
