class GlobalVars {
  static const String pcKey = "X-Project-ID";
  static const String pcSecret = "X-Project-Secret";

  static const String codeScoutDB = "code_scout.db";

  /// The floating button. One number, because the clamp needs the whole of it
  /// and the previous pair (a 50px image inside an 80px box) meant the button's
  /// real size was never written down anywhere.
  static const double buttonSize = 52;

  /// The platform minimum for anything you tap. Visible ink can be smaller;
  /// padding does the reach, which is what keeps a dense debug tool dense.
  static const double minTouchTarget = 44;
}
