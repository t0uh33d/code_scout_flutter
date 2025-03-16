// ignore_for_file: public_member_api_docs, sort_constructors_first, non_constant_identifier_names
import 'dart:convert';

import 'package:code_scout/src/config/config.dart';
import 'package:code_scout/src/csx_interface/overlay_manager.dart';
import 'package:flutter/material.dart' show BuildContext, Widget;

part 'code_scout_comms.dart';

typedef FreshContextFetcher = BuildContext Function();

// typedef CodeScoutSocketLogger = void Function(
//   bool Function(CodeScoutConfiguration configuration) shouldLog,
//   OutputEvent? outputEvent,
// );

class CodeScout {
  static final CodeScout instance = CodeScout._i();

  static final OverlayManager _overlayManager = OverlayManager();

  CodeScout._i();

  factory CodeScout() => instance;

  // late CodeScoutConfiguration _terimalLoggingConfigutation;

  // static CodeScoutSocketLogger? _codeScoutSocketLogger;

  static FreshContextFetcher? fetcher;

  // void bindSocketLogger(CodeScoutSocketLogger codeScoutSocketLogger) {
  //   _codeScoutSocketLogger = codeScoutSocketLogger;
  // }

  // void unbindSocketLogger() {
  //   _codeScoutSocketLogger = null;
  // }

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

  late CodeScoutConfiguration _configuration;

  void init({
    required CodeScoutConfiguration configuration,
    Widget? overlayChild,
    required BuildContext context,
    FreshContextFetcher? freshContextFetcher,
  }) {
    _configuration = configuration;

    fetcher = freshContextFetcher;

    if (_overlayManager.context == null) {
      if (overlayChild != null) _overlayManager.overlayChild = overlayChild;
      _overlayManager.context = context;
      _overlayManager.removeOverlay();
      _overlayManager.createOverlayEntry();
      isIconHidden = false;
    }
  }
}
