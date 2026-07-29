import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ThemePreferenceStore {
  ThemeMode read();

  Future<void> write(ThemeMode mode);
}

class SharedPreferencesThemePreferenceStore implements ThemePreferenceStore {
  SharedPreferencesThemePreferenceStore._(this._preferences);

  static const preferenceKey = 'voltrike.dark_mode.v1';

  final SharedPreferencesWithCache _preferences;

  static Future<SharedPreferencesThemePreferenceStore> create() async {
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: <String>{preferenceKey},
      ),
    );
    return SharedPreferencesThemePreferenceStore._(preferences);
  }

  @override
  ThemeMode read() {
    return _preferences.getBool(preferenceKey) == true
        ? ThemeMode.dark
        : ThemeMode.light;
  }

  @override
  Future<void> write(ThemeMode mode) {
    return _preferences.setBool(preferenceKey, mode == ThemeMode.dark);
  }
}

class MemoryThemePreferenceStore implements ThemePreferenceStore {
  MemoryThemePreferenceStore([this._mode = ThemeMode.light]);

  ThemeMode _mode;

  @override
  ThemeMode read() => _mode;

  @override
  Future<void> write(ThemeMode mode) async {
    _mode = mode;
  }
}
