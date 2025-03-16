// ignore_for_file: public_member_api_docs, sort_constructors_first, non_constant_identifier_names
import 'dart:convert';

import 'package:code_scout/src/config/config.dart';
import 'package:code_scout/src/csx_interface/overlay_manager.dart';
import 'package:code_scout/src/log/log_entry.dart';
import 'package:code_scout/src/log/log_printer.dart';
import 'package:flutter/material.dart' show BuildContext;
import 'package:logger/logger.dart';

import 'log/log_level.dart';

part 'code_scout_comms.dart';

typedef FreshContextFetcher = BuildContext Function();

class CodeScout {
  static final CodeScout instance = CodeScout._i();

  CodeScout._i();

  factory CodeScout() => instance;

  FreshContextFetcher? fetcher;
  final OverlayManager _overlayManager = OverlayManager();

  CodeScoutConfiguration? _configuration;

  void init({
    CodeScoutConfiguration? configuration,
    FreshContextFetcher? freshContextFetcher,
  }) {
    _configuration = configuration;

    fetcher = freshContextFetcher;

    if (_overlayManager.context == null) {
      // if (overlayChild != null) _overlayManager.overlayChild = overlayChild;
      _overlayManager.context = freshContextFetcher?.call();
      _overlayManager.removeOverlay();
      _overlayManager.createOverlayEntry();
      isIconHidden = false;
    }
  }

  //  verbose(1000),
  // debug(2000),
  // info(3000),
  // warning(4000),
  // error(5000),
  // fatal(6000),

  void logVerbose(String message) {}

  void log({
    required LogLevel level,
    required dynamic message,
    dynamic error,
    StackTrace? stackTrace,
    Set<String>? tags,
    Map<String, dynamic>? metadata,
  }) {
    if (_configuration == null) {
      throw Exception('CodeScout is not initialized');
    }

    // create log entry
    LogEntry logEntry = LogEntry(
      level: level,
      message: message,
      error: error,
      stackTrace: stackTrace,
      tags: tags,
      metadata: metadata,
    );

    if (!_configuration!.logging.shouldLog(logEntry)) {
      return;
    }

    CSxPrinter printer = CSxPrinter(logEntry);

    printer.printToConsole();
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
