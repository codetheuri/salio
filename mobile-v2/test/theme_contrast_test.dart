import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salio/app/theme/app_colors.dart';
import 'package:salio/app/theme/app_theme.dart';

// Text must reach 4.5 : 1 against what it is drawn on, for shops in bright
// light (docs/10, §5; WCAG 2.1, 1.4.3).
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  const surfaces = {
    'background': AppColors.background,
    'surface': AppColors.surface,
  };
  const texts = {
    'textPrimary': AppColors.textPrimary,
    'textSecondary': AppColors.textSecondary,
    'primary': AppColors.primary,
    'debtRed': AppColors.debtRed,
    'paymentGreen': AppColors.paymentGreen,
    'error': AppColors.error,
  };

  for (final text in texts.entries) {
    for (final surface in surfaces.entries) {
      test('${text.key} on ${surface.key} is readable', () {
        expect(_contrast(text.value, surface.value), greaterThanOrEqualTo(4.5));
      });
    }
  }

  test('white on the primary colour (app bar, buttons) is readable', () {
    expect(
      _contrast(AppColors.onPrimary, AppColors.primary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(AppColors.onPrimary, AppColors.primaryDark),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('an unselected tab in the app bar is readable', () {
    final tabs = AppTheme.light.tabBarTheme;
    final dimmed = Color.alphaBlend(
      tabs.unselectedLabelColor!,
      AppColors.primary,
    );
    expect(_contrast(dimmed, AppColors.primary), greaterThanOrEqualTo(4.5));
    expect(tabs.labelColor, AppColors.onPrimary);
  });
}
