part of 'network_manager.dart';

class NetworkErrorData extends NetworkData {
  final String type;
  final String message;
  final dynamic response;
  final StackTrace? stackTrace;
  final DateTime timestamp;

  NetworkErrorData({
    required this.type,
    required this.message,
    this.response,
    this.stackTrace,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  // from map
  factory NetworkErrorData.fromMap(Map<String, dynamic> map) {
    return NetworkErrorData(
      type: map['type'],
      message: map['message'],
      response: map['response'],
      stackTrace: map['stack_trace'],
      timestamp: DateTime.parse(map['timestamp']),
    );
  }

  @override
  Map<String, dynamic> toMap() {
    StackTraceParser stackTraceParser = StackTraceParser(
      stackTrace: stackTrace,
      methodCount: 10,
    );

    return {
      'type': type,
      'message': message,
      'response': response,
      'stack_trace': stackTraceParser.formattedTrace.join('\n'),
      'timestamp': timestamp.toIso8601String(),
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

    logEntry = LogEntry(
      level: LogLevel.error,
      message: 'Network Error',
      sessionID: CodeScout.instance.currentSessionId,
      isNetworkCall: true,
      stackTrace: stackTrace,
      requestId: _request?.requestID,
      callPhase: NetworkCallPhase.error,
      metadata: toMap(),
    );

    return logEntry;
  }
}
