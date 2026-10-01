import 'package:flutter/material.dart' show Brightness;

enum RideType {
  eTrike(
    'e_trike',
    'E-Trike Regular',
    'Regular',
    'assets/images/etrike_black.png',
    'assets/images/etrike_white.png',
    2,
  ),
  eTuktuk(
    'electric_tuktuk',
    'E-Trike XL',
    'XL',
    'assets/images/etuktuk_black.png',
    'assets/images/etuktuk_white.png',
    4,
  );

  const RideType(
    this.value,
    this.label,
    this.selectorLabel,
    this.lightAssetPath,
    this.darkAssetPath,
    this.maximumPassengers,
  );

  final String value;
  final String label;
  final String selectorLabel;
  final String lightAssetPath;
  final String darkAssetPath;
  final int maximumPassengers;

  String assetPathFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkAssetPath : lightAssetPath;

  bool canCarry(int passengerCount) => passengerCount <= maximumPassengers;

  static RideType fromValue(Object? value) {
    final normalized = value?.toString().toLowerCase().replaceAll(
      RegExp(r'[^a-z]'),
      '',
    );
    return switch (normalized) {
      'electrictuktuk' ||
      'etuktuk' ||
      'electrictricycle' ||
      'etrikexl' => RideType.eTuktuk,
      _ => RideType.eTrike,
    };
  }
}
