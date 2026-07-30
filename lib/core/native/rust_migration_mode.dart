enum RustMigrationMode {
  off,
  shadow,
  on;

  static const _legacyEnvironmentValue = String.fromEnvironment(
    'VOLTRIKE_RUST_MODE',
    defaultValue: 'off',
  );

  static RustMigrationMode fromEnvironment() {
    return parse(_legacyEnvironmentValue);
  }

  static RustMigrationMode geometryFromEnvironment() {
    return parse(
      const String.fromEnvironment(
        'VOLTRIKE_GEOMETRY_MODE',
        defaultValue: _legacyEnvironmentValue,
      ),
    );
  }

  static RustMigrationMode psgcFromEnvironment() {
    return parse(
      const String.fromEnvironment(
        'VOLTRIKE_PSGC_MODE',
        defaultValue: _legacyEnvironmentValue,
      ),
    );
  }

  static RustMigrationMode geometryProximityFromEnvironment() {
    return parse(
      const String.fromEnvironment(
        'VOLTRIKE_GEOMETRY_PROXIMITY_MODE',
        defaultValue: 'off',
      ),
    );
  }

  static RustMigrationMode navigationFromEnvironment() {
    return parse(
      const String.fromEnvironment(
        'VOLTRIKE_NAVIGATION_MODE',
        defaultValue: _legacyEnvironmentValue,
      ),
    );
  }

  static RustMigrationMode parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'shadow' => RustMigrationMode.shadow,
      'on' => RustMigrationMode.on,
      _ => RustMigrationMode.off,
    };
  }
}
