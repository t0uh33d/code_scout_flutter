import 'package:uuid/uuid.dart';

import 'log_level.dart';

class LogEntry {
  final String id;
  final LogLevel level;
  final dynamic message;
  final dynamic error;
  final StackTrace? stackTrace;
  final Map<String, dynamic>? metadata;
  final Set<String>? tags;
  final DateTime? timestamp;

  LogEntry({
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
    this.metadata,
    this.tags = const {},
  })  : id = const Uuid().v4(),
        timestamp = DateTime.now().toUtc();
}
