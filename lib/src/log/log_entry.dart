import 'log_level.dart';

class LogEntry {
  final LogLevel level;
  final String message;
  final dynamic error;
  final StackTrace? stackTrace;
  final Map<String, dynamic>? metadata;
  final Set<String> tags;

  LogEntry({
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
    this.metadata,
    this.tags = const {},
  });
}
