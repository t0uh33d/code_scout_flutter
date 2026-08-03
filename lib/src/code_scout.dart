// ignore_for_file: public_member_api_docs, sort_constructors_first, non_constant_identifier_names
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:code_scout/src/config/config.dart';
import 'package:code_scout/src/csx_interface/overlay_manager.dart';
import 'package:code_scout/src/live/live_session_client.dart';
import 'package:code_scout/src/log/log_entry.dart';
import 'package:code_scout/src/log/log_persistence_service.dart';
import 'package:code_scout/src/log/log_sync_worker.dart';
import 'package:code_scout/src/session/device_profile.dart';
import 'package:code_scout/src/session/session_record.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart' show BuildContext;
import 'package:uuid/uuid.dart';

import 'log/log_level.dart';

part 'code_scout_comms.dart';

typedef FreshContextFetcher = BuildContext Function();

class CodeScout {
  static final CodeScout instance = CodeScout._i();

  CodeScout._i();

  factory CodeScout() => instance;

  FreshContextFetcher? fetcher;
  final OverlayManager _overlayManager = OverlayManager();

  // Not `late`: interceptors and log calls may fire before init(), and an
  // observability library must never crash the app it observes. init()
  // replaces both with the real values.
  CodeScoutConfiguration _configuration = CodeScoutConfiguration();

  String _currentSessionId = const Uuid().v4();

  String get currentSessionId => _currentSessionId;

  /// The record for this launch. Null until [init] has stored it — logging
  /// works regardless, since every log carries its own session id.
  SessionRecord? _session;

  SessionRecord? get currentSession => _session;

  CodeScoutConfiguration get configuration => _configuration;

  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  void setContext(BuildContext context) {
    if (_overlayManager.context != null) {
      dev.log('Warning: CodeScout context is already set, overriding it.');
    }
    _overlayManager.context = context;
  }

  Future<void> init({
    CodeScoutConfiguration? configuration,
    FreshContextFetcher? freshContextFetcher,
  }) async {
    if (_isInitialized) {
      throw Exception('CodeScout is already initialized.');
    }

    _configuration = configuration ?? CodeScoutConfiguration();

    fetcher = freshContextFetcher;

    _currentSessionId = const Uuid().v4();

    if (_overlayManager.context == null) {
      _overlayManager.context = freshContextFetcher?.call();
      _overlayManager.removeOverlay();
      _overlayManager.createOverlayEntry();
      isIconHidden = false;
    }

    _isInitialized = true;

    await _startSession();

    final creds = _configuration.projectCredentials;
    if (creds != null && await creds.valid == true) {
      LogSyncWorker.i.start();
    }

    // Drawn once, here, and not per log. A launch is either recorded or it is
    // not, so its timeline is whole either way — and a sampled-out launch pays
    // nothing after this line, since the gate sits above the SQLite write.
    //
    // After the credential check on purpose: that call is what fetches the
    // project's server-side rate.
    _sampledIn = drawSession(
      _configuration.logging.effectiveSampleRate(creds?.serverSampleRate),
    );
  }

  bool _sampledIn = true;

  /// Whether this launch is being recorded. False only when session sampling
  /// left it out, which nothing else in the SDK ever changes mid-launch.
  bool get isSessionSampledIn => _sampledIn;

  /// A launch is normally either drawn in or out by [init]. Tests need to say
  /// which, because a coin toss is not something to assert against.
  @visibleForTesting
  set isSessionSampledIn(bool value) => _sampledIn = value;

  /// Records this launch: which install it is, what it is running on, and when
  /// it started.
  ///
  /// Failing here must never fail init. Logs carry their session id whether or
  /// not this row exists, so the worst case is a dashboard row that says
  /// "Unknown device" — which is a great deal better than an app that will not
  /// start because a platform channel did not answer.
  Future<void> _startSession() async {
    final now = DateTime.now().toUtc();
    _session = SessionRecord(id: _currentSessionId, startedAt: now, lastSeenAt: now);

    try {
      final installationId = await LogPersistenceService.i.installationId();
      final profile = await DeviceProfile.collect(
        captureDevice: _configuration.logging.captureDeviceInfo,
        captureApp: _configuration.logging.captureAppContext,
      );
      _session = _session!.copyWith(
        installationId: installationId,
        profile: profile,
      );
      await LogPersistenceService.i.saveSession(_session!);
    } catch (e, st) {
      dev.log('CodeScout: could not record the session: $e', stackTrace: st);
    }
  }

  /// Starts streaming this launch to the dashboard, using a code minted there.
  ///
  /// Returns true once the server has accepted the pairing. Never throws — a
  /// mistyped code comes back as false with the reason in
  /// [LiveSessionClient.i].`error`, because this is driven from a button drawn
  /// over somebody else's running app.
  ///
  /// Streaming is additional, never a replacement: logs keep going to the
  /// console, the overlay and SQLite whether or not anyone is watching, and a
  /// live session that drops takes nothing with it.
  Future<bool> startLiveSession(String code) {
    return LiveSessionClient.i.start(
      code: code,
      configuration: _configuration,
      currentSessionId: _currentSessionId,
      session: _session,
    );
  }

  /// Stops streaming. The dashboard sees the device leave.
  Future<void> stopLiveSession() => LiveSessionClient.i.stop();

  /// Whether this launch is being streamed right now.
  bool get isLiveStreaming => LiveSessionClient.i.isLive;

  /// Names the person using the app. Identity is opt-in and is never inferred,
  /// so nothing appears against a session until this is called.
  ///
  /// [id] is stored and never parsed — hash it first if you would rather Code
  /// Scout never held the real thing. [traits] are attached to this session
  /// rather than to the person, because what matters while debugging is what
  /// was true when it broke.
  ///
  /// Safe to call at any point in a launch. The session record is re-sent with
  /// every batch, so a call made ten minutes in reaches the dashboard on the
  /// next sync.
  Future<void> setUser(String? id, {Map<String, dynamic>? traits}) async {
    final session = _session;
    if (session == null) return;

    _session = session.copyWith(
      userId: id,
      clearUser: id == null,
      metadata: traits,
      clearMetadata: traits == null && id == null,
      lastSeenAt: DateTime.now().toUtc(),
    );

    try {
      await LogPersistenceService.i.saveSession(_session!);
    } catch (e, st) {
      dev.log('CodeScout: could not store the user: $e', stackTrace: st);
    }
  }

  /// Moves this launch's last-seen to now. Called by the sync worker, so the
  /// dashboard's idea of how long a session has been running tracks reality
  /// rather than stopping at the moment the app started.
  Future<void> touchSession() async {
    final session = _session;
    if (session == null) return;

    _session = session.copyWith(lastSeenAt: DateTime.now().toUtc());
    try {
      await LogPersistenceService.i.saveSession(_session!);
    } catch (_) {
      // A stale last-seen is not worth failing a sync over.
    }
  }

  Future<void> logMessage({
    required LogLevel level,
    required String message,
    dynamic error,
    StackTrace? stackTrace,
    Set<String>? tags,
    Map<String, dynamic>? metadata,
  }) async {
    LogEntry logEntry = LogEntry(
      level: level,
      message: message,
      error: error,
      stackTrace: stackTrace,
      tags: tags,
      metadata: metadata,
      sessionID: CodeScout.instance.currentSessionId,
    );

    await logEntry.processLogEntry();
  }

  /// Fire-and-forget convenience method. Errors are caught internally
  /// so they never crash the host app. Use [logMessage] if you need
  /// to await persistence.
  void log({
    required LogLevel level,
    required String message,
    dynamic error,
    StackTrace? stackTrace,
    Set<String>? tags,
    Map<String, dynamic>? metadata,
  }) {
    logMessage(
      level: level,
      message: message,
      error: error,
      stackTrace: stackTrace,
      tags: tags,
      metadata: metadata,
    ).catchError((Object e, StackTrace st) {
      // Use dart:developer log to avoid recursion
      dev.log('CodeScout: log failed: $e', stackTrace: st);
    });
  }

  // ---------------------------------------------------------------------------
  // Level-specific shorthand methods
  // ---------------------------------------------------------------------------

  /// Log a verbose message.
  void v(String message, {dynamic error, StackTrace? stackTrace, Set<String>? tags, Map<String, dynamic>? metadata}) =>
      log(level: LogLevel.verbose, message: message, error: error, stackTrace: stackTrace, tags: tags, metadata: metadata);

  /// Log a debug message.
  void d(String message, {dynamic error, StackTrace? stackTrace, Set<String>? tags, Map<String, dynamic>? metadata}) =>
      log(level: LogLevel.debug, message: message, error: error, stackTrace: stackTrace, tags: tags, metadata: metadata);

  /// Log an info message.
  void i(String message, {dynamic error, StackTrace? stackTrace, Set<String>? tags, Map<String, dynamic>? metadata}) =>
      log(level: LogLevel.info, message: message, error: error, stackTrace: stackTrace, tags: tags, metadata: metadata);

  /// Log a warning message.
  void w(String message, {dynamic error, StackTrace? stackTrace, Set<String>? tags, Map<String, dynamic>? metadata}) =>
      log(level: LogLevel.warning, message: message, error: error, stackTrace: stackTrace, tags: tags, metadata: metadata);

  /// Log an error message.
  void e(String message, {dynamic error, StackTrace? stackTrace, Set<String>? tags, Map<String, dynamic>? metadata}) =>
      log(level: LogLevel.error, message: message, error: error, stackTrace: stackTrace, tags: tags, metadata: metadata);

  /// Log a fatal message.
  void f(String message, {dynamic error, StackTrace? stackTrace, Set<String>? tags, Map<String, dynamic>? metadata}) =>
      log(level: LogLevel.fatal, message: message, error: error, stackTrace: stackTrace, tags: tags, metadata: metadata);

  /// Uploads whatever is waiting, now, and completes when it has landed or
  /// failed. Normally the worker does this on its own schedule.
  ///
  /// Worth calling when the app is about to stop being able to: going to the
  /// background, or signing a user out. Everything the scheduled cycle does
  /// still applies, so a call while one is already running is not a second
  /// upload, and nothing is deleted locally until the server has taken it.
  Future<void> flush() => LogSyncWorker.i.flush();

  Future<void> dispose() async {
    LogSyncWorker.i.stop();
    await LogPersistenceService.i.close();
    _isInitialized = false;
  }

  // icon visibility
  bool isIconHidden = true;

  void hideIcon() {
    _overlayManager.removeOverlay();
    isIconHidden = true;
  }

  void showIcon() {
    _overlayManager.createOverlayEntry();
    isIconHidden = false;
  }

  void toggleIcon() {
    if (isIconHidden) {
      showIcon();
    } else {
      hideIcon();
    }
  }
}
