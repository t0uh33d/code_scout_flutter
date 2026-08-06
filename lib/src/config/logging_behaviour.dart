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

  /// The share of app launches that are recorded at all, 0.0 to 1.0.
  ///
  /// Sampling is per session rather than per log, so a launch that is kept
  /// keeps every one of its logs. Sampling individual logs would leave gaps in
  /// a timeline that looked like the app doing nothing.
  ///
  /// The drawn result holds for the whole launch, and the server can lower it
  /// per project but never raise it. Console output and the overlay are never
  /// sampled — those cost nothing and are what you are watching while you work.
  final double sessionSampleRate;

  LoggingBehavior({
    this.enabledTags = const {'*'},
    this.allowUntagged = true,
    this.minimumLevel = LogLevel.info,
    this.captureDeviceInfo = true,
    this.captureAppContext = true,
    this.printToConsole = kDebugMode,
    this.includeCurrentStackTrace = false,
    this.sessionSampleRate = 1.0,
  });

  /// The rate actually used for this launch: whichever of the app's own rate
  /// and the project's server-side rate is lower.
  ///
  /// The lower of the two, deliberately. A server can ask a noisy app to send
  /// less, which is the point of having the setting at all, but it can never
  /// make an app send more than its developer agreed to. An unreachable or
  /// unparseable server leaves [sessionSampleRate] alone rather than assuming
  /// anything.
  double effectiveSampleRate([double? remote]) {
    final local = _clampRate(sessionSampleRate);
    if (remote == null) return local;
    final server = _clampRate(remote);
    return server < local ? server : local;
  }

  bool shouldLog(LogEntry entry) {
    // System logs are the SDK's own record — a dashboard edit to a local
    // database, not something the app called. minimumLevel exists to control
    // the app's volume, and system's value (500) sits below even verbose, so
    // without this exemption the default config silently drops every one and
    // an audit line is never written anywhere.
    if (entry.level == LogLevel.system) return true;

    if (entry.level.value < minimumLevel.value) return false;
    if (enabledTags.contains('*')) return true;

    final tags = entry.tags;
    if (tags == null || tags.isEmpty) return allowUntagged;
    return tags.any(enabledTags.contains);
  }
}

/// Decides whether this launch is one of the recorded ones.
///
/// Drawn once per launch rather than per log, so a session that is kept keeps
/// its whole timeline. The two ends short-circuit: the common case of 1.0 must
/// not depend on a random number coming out right.
///
/// [random] returns a value in [0, 1) and exists for the tests.
bool drawSession(double rate, {double Function()? random}) {
  final r = _clampRate(rate);
  if (r >= 1) return true;
  if (r <= 0) return false;
  return (random ?? Random().nextDouble)() < r;
}

/// Keeps a rate inside 0.0 to 1.0. A NaN reads as 1.0, because a broken number
/// must not be the reason logging silently stopped.
double _clampRate(double rate) {
  if (rate.isNaN) return 1.0;
  if (rate <= 0) return 0.0;
  if (rate >= 1) return 1.0;
  return rate;
}
