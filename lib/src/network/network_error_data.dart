part of 'network_manager.dart';

class NetworkErrorData extends NetworkData {
  final String type;
  final String message;
  final dynamic response;
  final StackTrace? stackTrace;
  final DateTime timestamp;

  /// The status code, when the failure had one.
  ///
  /// dio rejects 4xx and 5xx by default, so those arrive here rather than as a
  /// response, and the code used to be dropped on the floor. That left a dio
  /// app unable to tell a 401 from a 504 anywhere: not in the overlay, and not
  /// on the dashboard either, since `ExtractNetworkMeta` promotes
  /// `status_code` out of this same map.
  ///
  /// Null for a transport failure, which genuinely has no code.
  final int? statusCode;

  NetworkErrorData({
    required this.type,
    required this.message,
    this.response,
    this.stackTrace,
    this.statusCode,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  // from map
  factory NetworkErrorData.fromMap(Map<String, dynamic> map) {
    return NetworkErrorData(
      type: map['type'],
      message: map['message'],
      response: map['response'],
      stackTrace: map['stack_trace'],
      statusCode: map['status_code'],
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
      // Top level, because that is where the server's ExtractNetworkMeta looks
      // for it. Omitted rather than sent as null when there is no code, so a
      // transport failure does not claim to have one.
      if (statusCode != null) 'status_code': statusCode,
      'response': Redactor.body(response),
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
      tags: {'network'},
      metadata: toMap(),
    );

    return logEntry;
  }
}
