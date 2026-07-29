import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_preference_store.dart';

final themePreferenceStoreProvider = Provider<ThemePreferenceStore>((ref) {
  return MemoryThemePreferenceStore();
});

final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) {
    return ThemeModeController(ref.watch(themePreferenceStoreProvider));
  },
);

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._store) : super(_store.read());

  final ThemePreferenceStore _store;

  bool get isDarkMode => state == ThemeMode.dark;

  Future<bool> setDarkMode(bool enabled) async {
    final previous = state;
    final next = enabled ? ThemeMode.dark : ThemeMode.light;
    if (next == previous) return true;

    state = next;
    try {
      await _store.write(next);
      return true;
    } catch (_) {
      state = previous;
      return false;
    }
  }
}
