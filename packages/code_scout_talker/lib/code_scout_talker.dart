import 'package:code_scout/code_scout.dart' as cs;
import 'package:flutter/foundation.dart';
import 'package:talker/talker.dart';

/// One Talker event translated into Code Scout's shape, before anything is
/// logged. Named so the translation can be asserted on directly.
typedef MappedLog = ({
  cs.LogLevel level,
  String message,
  Object? error,
  StackTrace? stackTrace,
  Set<String>? tags,
  Map<String, dynamic>? metadata,
});

/// Sends everything Talker logs to Code Scout as well.
///
/// Nothing about your logging changes. Talker keeps printing to the console,
/// `TalkerScreen` keeps working, every `talker_*` logger you already use keeps
/// working — this only adds a second reader, so the same logs also reach a
/// dashboard you can search across every device rather than only the one in
/// your hand.
///
/// ```dart
/// final talker = Talker(observer: const CodeScoutTalkerObserver());
/// ```
///
/// Set Code Scout up as usual with `CodeScout.instance.init`. Before that has
/// happened, and in a build with no credentials, this does nothing rather than
/// throwing or queueing.
class CodeScoutTalkerObserver extends TalkerObserver {
  /// [tags] are added to every log this forwards, on top of the tag taken from
  /// Talker's own log key. Useful for telling forwarded logs apart when an app
  /// calls both Talker and Code Scout directly.
  /// Says it is here as soon as it is built, like the other two companions, so
  /// Info can report all three the same way. Not const for that reason: a const
  /// constructor cannot run anything.
  CodeScoutTalkerObserver({this.tags = const {}}) {
    cs.NetworkManager.i.registerIntegration('talker');
  }

  final Set<String> tags;

  // Talker calls exactly one of these three per event: handle() dispatches to
  // onError or onException and returns before the log path, and only the
  // remaining path reaches onLog. So all three forward unconditionally without
  // anything being logged twice.
  //
  // Every one does its work inside a try/catch, for the same reason the Dio and
  // http interceptors do: a logging tool that can throw is a logging tool that
  // takes down the code it was meant to observe. Here that means an app's own
  // talker.info() call, which would be a poor trade for a dashboard row.

  @override
  void onLog(TalkerData log) {
    try {
      _forward(log, fallback: cs.LogLevel.info);
    } catch (_) {}
  }

  @override
  void onError(TalkerError err) {
    try {
      _forward(err, fallback: cs.LogLevel.error);
    } catch (_) {}
  }

  @override
  void onException(TalkerException err) {
    try {
      _forward(err, fallback: cs.LogLevel.error);
    } catch (_) {}
  }

  void _forward(TalkerData data, {required cs.LogLevel fallback}) {
    final m = map(data, fallback: fallback);
    cs.CodeScout.instance.log(
      level: m.level,
      message: m.message,
      error: m.error,
      stackTrace: m.stackTrace,
      tags: m.tags,
      metadata: m.metadata,
    );
  }

  /// The translation, separated from the sending of it.
  ///
  /// Visible for testing because this is where the behaviour is. Asserting only
  /// that forwarding does not throw would pass just as happily with every level
  /// mapped to info and every message left blank, so the mapping has to be
  /// checkable on its own.
  @visibleForTesting
  MappedLog map(TalkerData data, {required cs.LogLevel fallback}) {
    final cause = data.error ?? data.exception;
    return (
      level: _level(data.logLevel) ?? fallback,
      message: _message(data, cause),
      error: cause,
      stackTrace: data.stackTrace,
      tags: _tags(data),
      metadata: _metadata(data),
    );
  }

  /// Talker's message is nullable, and logging an error with no message is a
  /// normal thing to write: `talker.handle(e)`. Falling back to the exception
  /// keeps that row readable instead of putting an empty line in the viewer.
  String _message(TalkerData data, Object? cause) {
    final message = data.message;
    if (message != null && message.isNotEmpty) return message;
    if (cause != null) return cause.toString();
    return data.title ?? 'log';
  }

  /// Talker's `key` is the machine-readable log type: 'info' and 'error' for
  /// the built-in levels, but 'http-request', 'bloc-event' and so on once the
  /// companion loggers are in play. That second kind is what makes the
  /// dashboard's tag filter worth having, and carrying both costs nothing.
  Set<String>? _tags(TalkerData data) {
    final key = data.key;
    if (key == null || key.isEmpty) {
      return tags.isEmpty ? null : tags;
    }
    return {...tags, key};
  }

  /// Talker's title is display text ('HTTP Request'), not an identifier, so it
  /// goes in metadata rather than a tag, where the capitals and spaces would
  /// make a mess of the filter chips. 'log' is Talker's default and says
  /// nothing, so it is dropped.
  Map<String, dynamic>? _metadata(TalkerData data) {
    final title = data.title;
    if (title == null || title.isEmpty || title == 'log') return null;
    return {'talker_title': title};
  }

  /// Talker has no fatal and Code Scout has no critical, so critical maps to
  /// fatal: both mean "the worst thing this logger has". Everything else lines
  /// up by name.
  ///
  /// Null means Talker set no level, and the caller answers that rather than
  /// this method: an untyped log is info, but an untyped *error* is not.
  cs.LogLevel? _level(LogLevel? level) {
    switch (level) {
      case LogLevel.critical:
        return cs.LogLevel.fatal;
      case LogLevel.error:
        return cs.LogLevel.error;
      case LogLevel.warning:
        return cs.LogLevel.warning;
      case LogLevel.info:
        return cs.LogLevel.info;
      case LogLevel.debug:
        return cs.LogLevel.debug;
      case LogLevel.verbose:
        return cs.LogLevel.verbose;
      case null:
        return null;
    }
  }
}
