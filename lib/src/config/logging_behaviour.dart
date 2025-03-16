part of 'config.dart';

class LoggingBehavior {
  final Set<String> enabledTags;
  final LogLevel minimumLevel;
  final bool captureDeviceInfo;
  final bool captureAppContext;
  final List<String> redactPatterns;
  final int maxLocalLogAgeDays;
  final bool printToConsole;

  LoggingBehavior({
    this.enabledTags = const {'*'}, // Wildcard for all tags
    this.minimumLevel = LogLevel.info,
    this.captureDeviceInfo = true,
    this.captureAppContext = true,
    this.redactPatterns = const ['password', 'token'],
    this.maxLocalLogAgeDays = 7,
    this.printToConsole = kDebugMode,
  });

  bool shouldLog(LogEntry entry) {
    final levelAllowed = entry.level.index >= minimumLevel.index;
    final tagAllowed =
        enabledTags.contains('*') || entry.tags.any(enabledTags.contains);
    return levelAllowed && tagAllowed;
  }
}
