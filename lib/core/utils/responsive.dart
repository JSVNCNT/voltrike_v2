import 'package:flutter/material.dart';

class Responsive {
  const Responsive._();

  // ===========================================================================
  // Screen Width
  // ===========================================================================

  static double width(BuildContext context) =>
      MediaQuery.of(context).size.width;

  // ===========================================================================
  // Screen Height
  // ===========================================================================

  static double height(BuildContext context) =>
      MediaQuery.of(context).size.height;

  // ===========================================================================
  // Orientation
  // ===========================================================================

  static bool isPortrait(BuildContext context) =>
      MediaQuery.of(context).orientation == Orientation.portrait;

  static bool isLandscape(BuildContext context) =>
      MediaQuery.of(context).orientation == Orientation.landscape;

  // ===========================================================================
  // Device Types
  // ===========================================================================

  static bool isSmallPhone(BuildContext context) =>
      width(context) < 360;

  static bool isPhone(BuildContext context) =>
      width(context) >= 360 &&
      width(context) < 600;

  static bool isLargePhone(BuildContext context) =>
      width(context) >= 600 &&
      width(context) < 720;

  static bool isTablet(BuildContext context) =>
      width(context) >= 720;

  // ===========================================================================
  // Content Width
  // ===========================================================================

  static double contentWidth(BuildContext context) {
    if (isTablet(context)) {
      return 650;
    }

    return width(context);
  }

  // ===========================================================================
  // Horizontal Padding
  // ===========================================================================

  static double horizontalPadding(BuildContext context) {
    if (isTablet(context)) return 40;
    if (isLargePhone(context)) return 28;
    return 20;
  }

  // ===========================================================================
  // Vertical Padding
  // ===========================================================================

  static double verticalPadding(BuildContext context) {
    if (isTablet(context)) return 32;
    return 20;
  }

  // ===========================================================================
  // Responsive Value
  // ===========================================================================

  static T value<T>({
    required BuildContext context,
    required T phone,
    T? largePhone,
    T? tablet,
  }) {
    if (isTablet(context) && tablet != null) {
      return tablet;
    }

    if (isLargePhone(context) && largePhone != null) {
      return largePhone;
    }

    return phone;
  }
}