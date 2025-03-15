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
  static final CodeScout i = CodeScout._i();

  static final OverlayManager overlayManager = OverlayManager();

  CodeScout._i();

  factory CodeScout() => i;

  static late CodeScoutLoggingConfiguration _terimalLoggingConfigutation;

  static final Logger _logger = Logger();

  static CodeScoutSocketLogger? _codeScoutSocketLogger;

  static FreshContextFetcher? fetcher;

  static void bindSocketLogger(CodeScoutSocketLogger codeScoutSocketLogger) {
    _codeScoutSocketLogger = codeScoutSocketLogger;
  }

  static void unbindSocketLogger() {
    _codeScoutSocketLogger = null;
  }

  static void init({
    required CodeScoutLoggingConfiguration terimalLoggingConfigutation,
    Widget? overlayChild,
    required BuildContext context,
    FreshContextFetcher? freshContextFetcher,
  }) {
    _terimalLoggingConfigutation = terimalLoggingConfigutation;

    fetcher = freshContextFetcher;

    if (overlayManager.context == null) {
      if (overlayChild != null) overlayManager.overlayChild = overlayChild;
      overlayManager.context = context;
      overlayManager.removeOverlay();
      overlayManager.createOverlayEntry();
      iconHidden = false;
    }
  }

  static bool iconHidden = true;

  static void hideIcon() {
    overlayManager.removeOverlay();
    iconHidden = true;
  }

  static void showIcon() {
    overlayManager.createOverlayEntry();
    iconHidden = false;
  }

  static void toggleIcon() {
    if (iconHidden) {
      showIcon();
    } else {
      hideIcon();
    }
  }

  static void logDevTrace(
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
  static void logDebug(
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

  static void logCrash(
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

  static void logError(
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

  static void logAnalytics(
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
