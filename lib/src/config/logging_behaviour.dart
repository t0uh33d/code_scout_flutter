part of 'config.dart';

class LoggingBehavior {
  /// Tags allowed through to capture. `{'*'}` allows every tag.
  ///
  /// This narrows *tagged* logs only — untagged logs are unaffected unless
  /// [allowUntagged] is false. Use [minimumLevel] to control overall volume.
  final Set<String> enabledTags;

  /// Whether logs carrying no tags are captured. Set false to capture only
  /// logs matching [enabledTags].
  final bool allowUntagged;

  final LogLevel minimumLevel;
  final bool captureDeviceInfo;
  final bool captureAppContext;
  final bool printToConsole;
  final bool includeCurrentStackTrace;

  LoggingBehavior({
    this.enabledTags = const {'*'},
    this.allowUntagged = true,
    this.minimumLevel = LogLevel.info,
    this.captureDeviceInfo = true,
    this.captureAppContext = true,
    this.printToConsole = kDebugMode,
    this.includeCurrentStackTrace = false,
  });

  bool shouldLog(LogEntry entry) {
    if (entry.level.value < minimumLevel.value) return false;
    if (enabledTags.contains('*')) return true;

    final tags = entry.tags;
    if (tags == null || tags.isEmpty) return allowUntagged;
    return tags.any(enabledTags.contains);
  }
}
