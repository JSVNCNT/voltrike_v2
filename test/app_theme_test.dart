import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/providers/theme_provider.dart';
import 'package:voltrike_v2/core/theme/app_semantic_colors.dart';
import 'package:voltrike_v2/core/theme/app_theme.dart';
import 'package:voltrike_v2/core/theme/fixed_light_theme.dart';
import 'package:voltrike_v2/core/theme/theme_preference_store.dart';
import 'package:voltrike_v2/features/common/presentation/widgets/settings_view.dart';

void main() {
  group('ThemeModeController', () {
    test('defaults to light and persists a dark selection', () async {
      final store = MemoryThemePreferenceStore();
      final controller = ThemeModeController(store);

      expect(controller.state, ThemeMode.light);
      expect(await controller.setDarkMode(true), isTrue);
      expect(controller.state, ThemeMode.dark);
      expect(store.read(), ThemeMode.dark);
    });

    test('restores the previous mode if persistence fails', () async {
      final controller = ThemeModeController(_FailingThemeStore());

      expect(await controller.setDarkMode(true), isFalse);
      expect(controller.state, ThemeMode.light);
    });
  });

  group('AppTheme', () {
    test('builds complete light and dark schemes with semantic colors', () {
      expect(AppTheme.lightTheme.brightness, Brightness.light);
      expect(AppTheme.darkTheme.brightness, Brightness.dark);
      expect(
        AppTheme.lightTheme.extension<AppSemanticColors>(),
        AppSemanticColors.light,
      );
      expect(
        AppTheme.darkTheme.extension<AppSemanticColors>(),
        AppSemanticColors.dark,
      );
      expect(
        AppTheme.darkTheme.scaffoldBackgroundColor,
        isNot(AppTheme.lightTheme.scaffoldBackgroundColor),
      );
    });

    test('dark text and important semantic pairs meet contrast targets', () {
      final theme = AppTheme.darkTheme;
      final scheme = theme.colorScheme;
      final semantic = theme.extension<AppSemanticColors>()!;

      expect(_contrast(scheme.onSurface, scheme.surface), greaterThan(4.5));
      expect(_contrast(scheme.onPrimary, scheme.primary), greaterThan(4.5));
      expect(
        _contrast(semantic.onSuccessContainer, semantic.successContainer),
        greaterThan(4.5),
      );
      expect(
        _contrast(semantic.onWarningContainer, semantic.warningContainer),
        greaterThan(4.5),
      );
      expect(
        _contrast(semantic.onChatAction, semantic.chatAction),
        greaterThan(4.5),
      );
      expect(
        _contrast(
          AppTheme.lightTheme.colorScheme.outline,
          AppTheme.lightTheme.colorScheme.surface,
        ),
        greaterThan(3),
      );
    });

    test('interactive pills and sheets use structural outlines', () {
      final theme = AppTheme.lightTheme;
      final outline = theme.colorScheme.outline;
      final segmentedSide = theme.segmentedButtonTheme.style?.side?.resolve(
        const <WidgetState>{},
      );
      final navigationShape =
          theme.navigationBarTheme.indicatorShape as RoundedRectangleBorder;
      final sheetShape = theme.bottomSheetTheme.shape as RoundedRectangleBorder;

      expect(segmentedSide?.color, outline);
      expect(segmentedSide?.width, 1.2);
      expect(theme.chipTheme.side?.color, outline);
      expect(navigationShape.side.color, outline);
      expect(sheetShape.side.color, outline);
      expect(sheetShape.side.width, 1.5);
    });
  });

  testWidgets('Settings toggle updates the shared theme immediately', (
    tester,
  ) async {
    final store = MemoryThemePreferenceStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [themePreferenceStoreProvider.overrideWithValue(store)],
        child: Consumer(
          builder: (context, ref, _) {
            final mode = ref.watch(themeModeProvider);
            return MaterialApp(
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: mode,
              home: Scaffold(body: VolTrikeSettingsView(onLogout: () {})),
            );
          },
        ),
      ),
    );

    expect(find.text('Change profile photo'), findsNothing);
    expect(find.text('System diagnostics'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('Dark mode'))).brightness,
      Brightness.light,
    );
    await tester.tap(find.text('Dark mode'));
    await tester.pumpAndSettle();

    expect(store.read(), ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.text('Dark mode'))).brightness,
      Brightness.dark,
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
  });

  testWidgets('FixedLightTheme keeps public content light', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: const FixedLightTheme(
          child: Scaffold(
            body: Text('Public content', key: Key('public-content')),
          ),
        ),
      ),
    );

    final context = tester.element(find.byKey(const Key('public-content')));
    expect(Theme.of(context).brightness, Brightness.light);
  });
}

class _FailingThemeStore implements ThemePreferenceStore {
  @override
  ThemeMode read() => ThemeMode.light;

  @override
  Future<void> write(ThemeMode mode) {
    return Future<void>.error(StateError('storage unavailable'));
  }
}

double _contrast(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground
      : background;
  final darker = identical(lighter, foreground) ? background : foreground;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}
