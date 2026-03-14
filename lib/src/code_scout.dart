// ignore_for_file: public_member_api_docs, sort_constructors_first, non_constant_identifier_names
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:code_scout/src/config/config.dart';
import 'package:code_scout/src/csx_interface/overlay_manager.dart';
import 'package:code_scout/src/log/log_entry.dart';
import 'package:code_scout/src/log/log_persistence_service.dart';
import 'package:code_scout/src/log/log_sync_worker.dart';
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

  late CodeScoutConfiguration _configuration;

  late String _currentSessionId;

  String get currentSessionId => _currentSessionId;

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

    if (_configuration.projectCredentials != null &&
        await _configuration.projectCredentials!.valid == true) {
      LogSyncWorker.i.start();
    }
  }

  Future<void> logMessage({
    required LogLevel level,
    required dynamic message,
    dynamic error,
    StackTrace? stackTrace,
    Set<String>? tags,
    Map<String, dynamic>? metadata,
  }) async {
    LogEntry logEntry = LogEntry(
      level: level,
      message: message is String ? message : message.toString(),
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
    required dynamic message,
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
