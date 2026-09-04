enum RideType {
  eTrike('e_trike', 'E-Trike', 'assets/images/etrike.png', 2),
  eTuktuk('electric_tuktuk', 'E-Tuktuk', 'assets/images/etuktuk.png', 4);

  const RideType(
    this.value,
    this.label,
    this.assetPath,
    this.maximumPassengers,
  );

  final String value;
  final String label;
  final String assetPath;
  final int maximumPassengers;

  bool canCarry(int passengerCount) => passengerCount <= maximumPassengers;

  static RideType fromValue(Object? value) {
    final normalized = value?.toString().toLowerCase().replaceAll(
      RegExp(r'[^a-z]'),
      '',
    );
    return switch (normalized) {
      'electrictuktuk' || 'etuktuk' || 'electrictricycle' => RideType.eTuktuk,
      _ => RideType.eTrike,
    };
  }
}
