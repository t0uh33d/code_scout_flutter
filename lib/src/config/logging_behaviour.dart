part of 'config.dart';

class LoggingBehavior {
  final Set<String> enabledTags;
  final LogLevel minimumLevel;
  final bool captureDeviceInfo;
  final bool captureAppContext;
  final bool printToConsole;
  final bool includeCurrentStackTrace;

  LoggingBehavior({
    this.enabledTags = const {'*'}, // Wildcard for all tags
    this.minimumLevel = LogLevel.info,
    this.captureDeviceInfo = true,
    this.captureAppContext = true,
    this.printToConsole = kDebugMode,
    this.includeCurrentStackTrace = false,
  });

  bool shouldLog(LogEntry entry) {
    final levelAllowed = entry.level.index >= minimumLevel.index;
    final tagAllowed = enabledTags.contains('*') ||
        (entry.tags != null && entry.tags!.any(enabledTags.contains));
    return levelAllowed && tagAllowed;
  }
}
