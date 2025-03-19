part of 'network_manager.dart';

enum NetworkCallPhase { request, response, error }

class NetworkRequestData extends NetworkData {
  final String method;
  final Uri url;
  final Map<String, dynamic>? headers;
  final dynamic body;
  final DateTime? timestamp;
  final String requestID;

  NetworkRequestData(
      {required this.method,
      required this.url,
      this.headers,
      this.body,
      this.timestamp,
      required this.requestID});

  // from map
  factory NetworkRequestData.fromMap(Map<String, dynamic> map) {
    return NetworkRequestData(
      method: map['method'],
      url: map['url'],
      headers: map['headers'],
      body: map['body'],
      timestamp: DateTime.parse(
        map['timestamp'],
      ),
      requestID: map['request_id'],
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'method': method,
      'url': url.toString(),
      'headers': headers,
      'body': body,
      'timestamp': timestamp?.toIso8601String(),
      'request_id': requestID,
    };
  }

  static String newRequestID() => const Uuid().v4();

  @override
  LogEntry generateLogEntry() {
    logEntry = LogEntry(
      level: LogLevel.debug,
      message: 'Network Request',
      sessionID: CodeScout.instance.currentSessionId,
      isNetworkCall: true,
      requestId: requestID,
      callPhase: NetworkCallPhase.request,
      metadata: toMap(),
      tags: {'network'},
    );

    return logEntry;
  }

  factory NetworkRequestData.fromLogEntry(LogEntry logEntry) {
    NetworkRequestData req = NetworkRequestData(
      method: logEntry.metadata?['method'],
      url: Uri.parse(logEntry.metadata?['url']),
      headers: logEntry.metadata?['headers'],
      body: logEntry.metadata?['body'],
      requestID: logEntry.requestId!,
    );

    return req;
  }
}
