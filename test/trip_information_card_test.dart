import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/theme/app_theme.dart';
import 'package:voltrike_v2/features/ride/tracking/widgets/trip_information_card.dart';

void main() {
  testWidgets('trip metric values remain visible on the card surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: TripInformationCard(
            pickup: 'Pickup',
            destination: 'Destination',
            distance: '1.2 km',
            duration: '8 min',
            fare: '₱75.00',
          ),
        ),
      ),
    );

    final context = tester.element(find.byType(TripInformationCard));
    final onSurface = Theme.of(context).colorScheme.onSurface;

    for (final value in ['1.2 km', '8 min', '₱75.00']) {
      final text = tester.widget<Text>(find.text(value));
      expect(text.style?.color, onSurface);
    }
  });

  testWidgets('empty route metrics show a useful loading value', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const Scaffold(
          body: TripInformationCard(
            pickup: '',
            destination: '',
            distance: '--',
            duration: '',
            fare: '--',
          ),
        ),
      ),
    );

    expect(find.text('Location unavailable'), findsNWidgets(2));
    expect(find.text('Updating…'), findsNWidgets(3));
  });
}
