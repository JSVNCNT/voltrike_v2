import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  // ---------------------------------------------------------------------------
  // Brand
  // ---------------------------------------------------------------------------

  static const Color primary = Color(0xFF006F73);
  static const Color primaryDark = Color(0xFF063B3C);
  static const Color primaryLight = Color(0xFF35B9B9);
  static const Color brandAccent = Color(0xFF008B8B);
  static const Color primaryContainer = Color(0xFFD8EFEF);

  /// High-contrast route color used over both light and dark Google Maps.
  ///
  /// The route is traffic-aware; live congestion remains visible through the
  /// native traffic layer instead of encoding an unverified traffic level in
  /// the route stroke itself.
  static const Color trafficRoute = Color(0xFF3B82F6);

  /// Passenger's unconfirmed pickup-to-destination route preview.
  static const Color passengerRoutePreview = Color(0xFFFACC15);
  static const Color passengerRoutePreviewCasing = Color(0xFF4B3A00);

  /// Enforced operating-area overlay. The alpha keeps the underlying map legible.
  static const Color restrictedAreaFill = Color(0x40EF4444);
  static const Color restrictedAreaBorder = Color(0xFFB91C1C);

  // ---------------------------------------------------------------------------
  // Background
  // ---------------------------------------------------------------------------

  static const Color background = Color(0xFFF7F9FA);
  static const Color surface = Colors.white;
  static const Color scaffold = Color(0xFFF7F9FA);

  // ---------------------------------------------------------------------------
  // Text
  // ---------------------------------------------------------------------------

  static const Color textPrimary = Color(0xFF173234);
  static const Color textSecondary = Color(0xFF557072);
  static const Color textHint = Color(0xFF789092);
  static const Color textWhite = Colors.white;

  // ---------------------------------------------------------------------------
  // Status
  // ---------------------------------------------------------------------------

  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFF9A825);
  static const Color error = Color(0xFFD32F2F);
  static const Color info = Color(0xFF1976D2);

  // Ride communication and safety actions. Kept semantic so a future dark
  // color scheme can replace them centrally without changing ride widgets.
  static const Color callAction = Color(0xFF2E7D32);
  static const Color chatAction = Color(0xFF0288D1);
  static const Color reportAction = Color(0xFFF57C00);
  static const Color safetyAction = Color(0xFF006F73);

  // ---------------------------------------------------------------------------
  // Border
  // ---------------------------------------------------------------------------

  static const Color border = Color(0xFFD8E4E4);

  // ---------------------------------------------------------------------------
  // Misc
  // ---------------------------------------------------------------------------

  static const Color divider = Color(0xFFE5EEEE);
  static const Color disabled = Color(0xFFBDBDBD);

  static const Color online = Color(0xFF4CAF50);
  static const Color offline = Color(0xFF9E9E9E);

  static const Color rating = Color(0xFFFFC107);
}
