import 'package:flutter/material.dart';

/// Screen widths where the layout changes, in dp (docs/10, §2.2).
abstract final class Breakpoints {
  /// From here up (phones in landscape, small tablets, open foldables)
  /// navigation moves from the bottom bar to a side rail.
  static const double medium = 600;

  /// From here up, list screens show the chosen item in a second pane.
  static const double expanded = 840;

  /// From here up the side rail shows labels beside its icons.
  static const double large = 1200;

  /// The widest a form grows.
  static const double formWidth = 720;

  /// The widest a list grows.
  static const double listWidth = 900;
}

/// The body of a screen: kept clear of the areas the system draws over, and
/// at a readable width, centred, on wide screens.
///
/// Since Android 15 apps draw edge to edge, so without this the last button
/// of a form ends up under the gesture or 3-button navigation bar, and in
/// landscape content goes under the camera cutout. The top is left to the
/// app bar, and the bottom to the app-wide SafeArea in app.dart.
class ReadableWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ReadableWidth({
    super.key,
    required this.child,
    this.maxWidth = Breakpoints.formWidth,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}
