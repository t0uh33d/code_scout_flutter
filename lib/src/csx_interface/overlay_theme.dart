import 'package:flutter/material.dart';

/// The dashboard's palette, so the overlay and the web app are recognisably
/// the same product. Values come from DESIGN.md.
class CSxColors {
  const CSxColors._();

  static const background = Color(0xFF111214);
  static const card = Color(0xFF17181C);
  static const elevated = Color(0xFF1B1C1D);
  static const border = Color(0xFF21262D);
  static const primary = Color(0xFF078DEE);
  static const muted = Color(0xFF8B949E);
  static const faint = Color(0xFF6E7681);
  static const white = Color(0xFFFFFFFF);

  static const fatal = Color(0xFFFF4D6A);
  static const error = Color(0xFFF85149);
  static const warning = Color(0xFFD29922);
  static const info = Color(0xFF0084FF);
  static const debug = Color(0xFF3FB950);
  static const verbose = Color(0xFF8B949E);
}

/// levelColor keeps the badges in the overlay the same colours as the badges
/// on the dashboard, so a level reads the same in both places.
Color levelColor(String level) {
  switch (level) {
    case 'fatal':
      return CSxColors.fatal;
    case 'error':
      return CSxColors.error;
    case 'warning':
      return CSxColors.warning;
    case 'info':
      return CSxColors.info;
    case 'debug':
      return CSxColors.debug;
    case 'verbose':
      return CSxColors.verbose;
    default:
      return CSxColors.muted;
  }
}

const mono = TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Menlo', 'Courier']);
