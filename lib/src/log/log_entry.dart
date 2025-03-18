import 'dart:math';

import 'package:code_scout/src/code_scout.dart';
import 'package:code_scout/src/utils/stack_trace_parser.dart';
import 'package:uuid/uuid.dart';

import 'log_level.dart';

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

  List<String>? _formattedStackTrace;

  List<String>? get formattedStackTrace => _formattedStackTrace;

  LogEntry({
    required this.level,
    required this.message,
    required this.sessionID,
    this.error,
    this.stackTrace,
    this.metadata,
    this.tags = const {},
  })  : id = const Uuid().v4(),
        timestamp = DateTime.now().toUtc() {
    bool includeCurrentStackTrace =
        CodeScout.instance.configuration?.logging.includeCurrentStackTrace ??
            false;

    if (!includeCurrentStackTrace && stackTrace == null) {
      return;
    }

    StackTraceParser parser = StackTraceParser(
      stackTrace: stackTrace == null && includeCurrentStackTrace
          ? StackTrace.current
          : stackTrace,
      methodCount: 3,
    );

    parser.parse();

    _formattedStackTrace = parser.formattedTrace;
  }
}
