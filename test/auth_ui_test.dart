import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/theme/app_theme.dart';
import 'package:voltrike_v2/features/auth/presentation/screens/intro/intro_screen.dart';
import 'package:voltrike_v2/features/auth/presentation/widgets/loading_overlay.dart';
import 'package:voltrike_v2/features/auth/presentation/widgets/registration_step_indicator.dart';

void main() {
  testWidgets('intro keeps passenger and driver choices clear at large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: IntroScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome to VolTrike'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Continue as passenger'), findsOneWidget);
    expect(find.text('Apply as a driver'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('driver registration progress exposes step and percentage', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: RegistrationStepIndicator(currentStep: 4, totalSteps: 5),
        ),
      ),
    );

    expect(find.text('Step 4 of 5'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.value, 0.8);
  });

  testWidgets('compact image preparation overlay stays small at large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(3)),
          child: Scaffold(
            body: LoadingOverlay(
              isLoading: true,
              compact: true,
              message: 'Preparing image',
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    final indicator = find.byKey(const Key('compact-loading-indicator'));
    expect(indicator, findsOneWidget);
    expect(tester.getSize(indicator), const Size.square(56));
    expect(find.text('Preparing image'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
