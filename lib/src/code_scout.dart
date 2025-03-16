// ignore_for_file: public_member_api_docs, sort_constructors_first, non_constant_identifier_names
import 'dart:convert';
import 'dart:nativewrappers/_internal/vm/lib/ffi_allocation_patch.dart';

import 'package:code_scout/src/config/config.dart';
import 'package:code_scout/src/csx_interface/overlay_manager.dart';
import 'package:flutter/material.dart' show BuildContext, Widget;

part 'code_scout_comms.dart';

typedef FreshContextFetcher = BuildContext Function();

class CodeScout {
  static final CodeScout instance = CodeScout._i();

  static final OverlayManager _overlayManager = OverlayManager();

  CodeScout._i();

  factory CodeScout() => instance;

  static FreshContextFetcher? fetcher;

  CodeScoutConfiguration? _configuration;

  void init({
    CodeScoutConfiguration? configuration,
    FreshContextFetcher? freshContextFetcher,
  }) {
    _configuration = configuration;

    fetcher = freshContextFetcher;

    if (_overlayManager.context == null) {
      // if (overlayChild != null) _overlayManager.overlayChild = overlayChild;
      _overlayManager.context = freshContextFetcher.call();
      _overlayManager.removeOverlay();
      _overlayManager.createOverlayEntry();
      isIconHidden = false;
    }
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
