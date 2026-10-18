import 'package:flutter/material.dart';

/// Colour tokens from docs/05-design-system.md.
///
/// One change from that document: [textSecondary] is Material grey 700
/// (#616161) instead of #757575, which measures 4.2 : 1 on [background],
/// under the 4.5 : 1 that text needs in a bright shop (docs/10, §5).
/// test/theme_contrast_test.dart checks every text colour against the
/// surfaces it is drawn on.
abstract final class AppColors {
  static const primary = Color(0xFF00796B);
  static const primaryLight = Color(0xFFB2DFDB);
  static const primaryDark = Color(0xFF004D40);
  static const onPrimary = Color(0xFFFFFFFF);

  /// Debt amounts. Always beside a word or sign as well: colour is never the
  /// only signal (docs/10, §5).
  static const debtRed = Color(0xFFC62828);

  /// Payment amounts and "Cleared".
  static const paymentGreen = Color(0xFF2E7D32);

  /// Overdue markers: icons and fills only. At 2.9 : 1 on white it is too
  /// light for text.
  static const warningAmber = Color(0xFFF57F17);

  static const textPrimary = Color(0xFF212121);
  static const textSecondary = Color(0xFF616161);
  static const divider = Color(0xFFEEEEEE);
  static const background = Color(0xFFF5F5F5);
  static const surface = Color(0xFFFFFFFF);
  static const error = Color(0xFFD32F2F);
}
