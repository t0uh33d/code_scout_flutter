part of 'network_manager.dart';

abstract class NetworkData {
  Map<String, dynamic> toMap();

  LogEntry? _logEntry;

  LogEntry get logEntry {
    _logEntry ??= generateLogEntry();
    return _logEntry!;
  }

  set logEntry(LogEntry logEntry) {
    _logEntry = logEntry;
  }

  LogEntry generateLogEntry();
}
