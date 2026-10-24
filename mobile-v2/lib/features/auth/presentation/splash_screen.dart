import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';

/// Shown for the moment it takes to read which account is signed in.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: AppColors.primary,
    body: Center(
      child: Text(
        'Salio',
        style: TextStyle(
          color: AppColors.onPrimary,
          fontSize: 36,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
