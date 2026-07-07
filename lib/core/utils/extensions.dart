import 'package:flutter/material.dart';

import 'responsive.dart';

extension ContextExtensions on BuildContext {
  // ===========================================================================
  // Screen Size
  // ===========================================================================

  double get width => Responsive.width(this);

  double get height => Responsive.height(this);

  // ===========================================================================
  // Device Type
  // ===========================================================================

  bool get isSmallPhone => Responsive.isSmallPhone(this);

  bool get isPhone => Responsive.isPhone(this);

  bool get isLargePhone => Responsive.isLargePhone(this);

  bool get isTablet => Responsive.isTablet(this);

  // ===========================================================================
  // Padding
  // ===========================================================================

  double get horizontalPadding =>
      Responsive.horizontalPadding(this);

  double get verticalPadding =>
      Responsive.verticalPadding(this);

  // ===========================================================================
  // Theme
  // ===========================================================================

  ThemeData get theme => Theme.of(this);

  TextTheme get textTheme => Theme.of(this).textTheme;

  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  // ===========================================================================
  // Keyboard
  // ===========================================================================

  void hideKeyboard() {
    FocusScope.of(this).unfocus();
  }
}