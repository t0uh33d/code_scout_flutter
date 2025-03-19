import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/log/log_printer.dart';
import 'package:code_scout/src/utils/stack_trace_parser.dart';
import 'package:uuid/uuid.dart';

class LogEntry {
  final String id;
  final String sessionID;
  final LogLevel level;
  final dynamic message;
  final dynamic error;
  final StackTrace? stackTrace;
  final Map<String, dynamic>? metadata;
  final Set<String>? tags;
  final DateTime? timestamp;
  final bool isNetworkCall;

  // New network-specific properties
  final String? requestId;
  final NetworkCallPhase? callPhase;

  List<String>? _formattedStackTrace;

  List<String>? get formattedStackTrace => _formattedStackTrace;

  List<StackCallDetails>? _stackCallDetails;

  List<StackCallDetails>? get stackCallDetails => _stackCallDetails;

  LogEntry({
    required this.level,
    required this.message,
    required this.sessionID,
    this.error,
    this.stackTrace,
    this.metadata,
    this.tags = const {},
    this.isNetworkCall = false,
    this.requestId,
    this.callPhase,
  })  : id = const Uuid().v4(),
        timestamp = DateTime.now().toUtc() {
    bool includeCurrentStackTrace =
        CodeScout.instance.configuration?.logging.includeCurrentStackTrace ??
            false;

    if (!includeCurrentStackTrace && stackTrace == null || isNetworkCall) {
      return;
    }

    StackTraceParser parser = StackTraceParser(
      stackTrace: stackTrace == null && includeCurrentStackTrace
          ? StackTrace.current
          : stackTrace,
      methodCount: 10,
    );

    parser.parse();

    _formattedStackTrace = parser.formattedTrace;
    _stackCallDetails = parser.stackCallDetails;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'session_id': sessionID,
      'level': level.name,
      'message': message.toString(),
      'error': error.toString(),
      'stack_trace': _stackCallDetails?.map((e) => e.toJson()).toList(),
      'metadata': metadata,
      'tags': tags,
      'timestamp': timestamp?.toIso8601String(),
      'is_network_call': isNetworkCall,
      'request_id': requestId,
      'call_phase': callPhase?.name,
    };
  }

  void processLogEntry({NetworkData? networkData}) {
    CodeScoutConfiguration cfg = CodeScout.instance.configuration!;
    if (!cfg.logging.shouldLog(this)) {
      return;
    }

    CSxPrinter printer = CSxPrinter(this);

    printer.printToConsole(networkData: networkData);
  }
}
