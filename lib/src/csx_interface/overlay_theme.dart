import 'package:flutter/material.dart';

/// The dashboard's palette, so the overlay and the web app are recognisably
/// the same product. Values come from DESIGN.md.
class CSxColors {
  const CSxColors._();

  static const background = Color(0xFF111214);
  static const card = Color(0xFF17181C);
  static const elevated = Color(0xFF1B1C1D);
  static const border = Color(0xFF21262D);
  static const borderStrong = Color(0xFF30363D);
  static const primary = Color(0xFF078DEE);
  static const muted = Color(0xFF8B949E);
  static const white = Color(0xFFFFFFFF);

  /// For a fill that white sits on. White on [primary] is 3.47:1, under AA;
  /// on this it is 5.17:1.
  static const primaryDeep = Color(0xFF2563EB);

  /// Hairlines and disabled chrome. **Never text.** At 1.84:1 on [background]
  /// it is not readable at any size. Timestamps, breadcrumb ancestors and null
  /// cells all use [muted], which is 6.09:1.
  static const faint = Color(0xFF414143);

  static const fatal = Color(0xFFFF4D6A);
  static const error = Color(0xFFF85149);

  /// For a fill that white sits on. White on [error] is 3.35:1; on this it is
  /// 4.61:1. The floating button's badge is a 10px numeral, which cannot reach
  /// AA through the large-text rule.
  static const errorDeep = Color(0xFFDA3633);

  static const warning = Color(0xFFD29922);

  /// Lifted from #0084FF, which was 4.30:1 on its own 16% tint and is the most
  /// common badge in any log list. Keep the dashboard's token in step, or a
  /// level stops reading the same in both places.
  static const info = Color(0xFF339DFF);
  static const debug = Color(0xFF3FB950);
  static const verbose = Color(0xFF8B949E);
  static const system = Color(0xFFA371F7);
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
    case 'system':
      return CSxColors.system;
    default:
      return CSxColors.muted;
  }
}

const mono = TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Menlo', 'Courier']);
