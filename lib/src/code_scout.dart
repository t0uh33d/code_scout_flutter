// ignore_for_file: public_member_api_docs, sort_constructors_first, non_constant_identifier_names
import 'dart:convert';

import 'package:code_scout/src/codescout_interface/overlay_manager.dart';
import 'package:flutter/material.dart' show BuildContext, Widget;
import 'package:logger/logger.dart';

part 'code_scout_comms.dart';

typedef FreshContextFetcher = BuildContext Function();

typedef CodeScoutSocketLogger = void Function(
  bool Function(CodeScoutLoggingConfiguration configuration) shouldLog,
  OutputEvent? outputEvent,
);

class CodeScout {
  static final CodeScout instance = CodeScout._i();

  static final OverlayManager _overlayManager = OverlayManager();

  CodeScout._i();

  factory CodeScout() => instance;

  late CodeScoutLoggingConfiguration _terimalLoggingConfigutation;

  static final Logger _logger = Logger();

  static CodeScoutSocketLogger? _codeScoutSocketLogger;

  static FreshContextFetcher? fetcher;

  void bindSocketLogger(CodeScoutSocketLogger codeScoutSocketLogger) {
    _codeScoutSocketLogger = codeScoutSocketLogger;
  }

  void unbindSocketLogger() {
    _codeScoutSocketLogger = null;
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

  void init({
    required CodeScoutLoggingConfiguration terimalLoggingConfigutation,
    Widget? overlayChild,
    required BuildContext context,
    FreshContextFetcher? freshContextFetcher,
  }) {
    _terimalLoggingConfigutation = terimalLoggingConfigutation;

    fetcher = freshContextFetcher;

    if (_overlayManager.context == null) {
      if (overlayChild != null) _overlayManager.overlayChild = overlayChild;
      _overlayManager.context = context;
      _overlayManager.removeOverlay();
      _overlayManager.createOverlayEntry();
      isIconHidden = false;
    }
  }

  void logDevTrace(
    dynamic message, {
    DateTime? dateTime,
    Object? error,
    StackTrace? stackTrace,
  }) {
    bool avoidLogging = !_terimalLoggingConfigutation.isDebugMode ||
        !_terimalLoggingConfigutation.devTraces;

    OutputEvent? outputEvent = _logger.log(
      Level.trace,
      message,
      time: dateTime ?? DateTime.now(),
      error: error,
      stackTrace: stackTrace,
      onlyReturnOutput: avoidLogging,
    );

    _codeScoutSocketLogger?.call(
      (socketConfig) => socketConfig.devTraces,
      outputEvent,
    );
  }

  // Log a debug message
  void logDebug(
    dynamic message, {
    DateTime? dateTime,
    Object? error,
    StackTrace? stackTrace,
  }) {
    // Determine if logging should be avoided based on the logging configuration
    bool avoidLogging = !_terimalLoggingConfigutation.isDebugMode ||
        !_terimalLoggingConfigutation.devLogs;

    OutputEvent? outputEvent = _logger.log(
      Level.debug,
      message,
      time: dateTime ?? DateTime.now(),
      error: error,
      stackTrace: stackTrace,
      onlyReturnOutput: avoidLogging,
    );

    _codeScoutSocketLogger?.call(
      (socketConfig) => socketConfig.devLogs,
      outputEvent,
    );
  }

  void logCrash(
    dynamic message, {
    DateTime? dateTime,
    required Object? error,
    required StackTrace? stackTrace,
  }) {
    bool avoidLogging = !_terimalLoggingConfigutation.isDebugMode ||
        !_terimalLoggingConfigutation.crashLogs;

    OutputEvent? outputEvent = _logger.log(
      Level.fatal,
      message,
      time: dateTime ?? DateTime.now(),
      error: error,
      stackTrace: stackTrace,
      onlyReturnOutput: avoidLogging,
    );

    _codeScoutSocketLogger?.call(
      (socketConfig) => socketConfig.crashLogs,
      outputEvent,
    );
  }

  void logError(
    dynamic message, {
    DateTime? dateTime,
    Object? error,
    StackTrace? stackTrace,
  }) {
    bool avoidLogging = !_terimalLoggingConfigutation.isDebugMode ||
        !_terimalLoggingConfigutation.errorLogs;

    OutputEvent? outputEvent = _logger.log(
      Level.error,
      message,
      time: dateTime ?? DateTime.now(),
      error: error,
      stackTrace: stackTrace,
      onlyReturnOutput: avoidLogging,
    );

    _codeScoutSocketLogger?.call(
      (socketConfig) => socketConfig.errorLogs,
      outputEvent,
    );
  }

  void logAnalytics(
    dynamic message, {
    DateTime? dateTime,
    Object? error,
    StackTrace? stackTrace,
  }) {
    bool avoidLogging = !_terimalLoggingConfigutation.isDebugMode ||
        !_terimalLoggingConfigutation.analyticsLogs;

    OutputEvent? outputEvent = _logger.log(
      Level.warning,
      message,
      time: dateTime ?? DateTime.now(),
      error: error,
      stackTrace: stackTrace,
      onlyReturnOutput: avoidLogging,
    );

    _codeScoutSocketLogger?.call(
      (socketCofig) => socketCofig.analyticsLogs,
      outputEvent,
    );
  }
}

class CodeScoutLoggingConfiguration {
  bool devTraces;
  bool devLogs;
  bool networkCall;
  bool analyticsLogs;
  bool crashLogs;
  bool errorLogs;
  bool isDebugMode;

  CodeScoutLoggingConfiguration({
    this.devTraces = false,
    this.devLogs = false,
    this.networkCall = false,
    this.analyticsLogs = false,
    this.crashLogs = false,
    this.errorLogs = false,
    this.isDebugMode = false,
  });
}
