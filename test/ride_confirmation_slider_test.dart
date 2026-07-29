import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/features/ride/tracking/models/ride_action.dart';
import 'package:voltrike_v2/features/ride/tracking/widgets/ride_confirmation_slider.dart';

void main() {
  testWidgets('requires a full swipe from the thumb to confirm', (
    tester,
  ) async {
    var confirmations = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: RideConfirmationSlider(
                action: RidePrimaryAction.startTrip,
                onConfirmed: () => confirmations++,
              ),
            ),
          ),
        ),
      ),
    );

    final slider = find.byType(RideConfirmationSlider);
    final start = tester.getTopLeft(slider) + const Offset(24, 29);

    final shortGesture = await tester.startGesture(start);
    await shortGesture.moveBy(const Offset(100, 0));
    await shortGesture.up();
    await tester.pumpAndSettle();
    expect(confirmations, 0);

    final fullGesture = await tester.startGesture(start);
    await fullGesture.moveBy(const Offset(330, 0));
    await fullGesture.up();
    await tester.pumpAndSettle();
    expect(confirmations, 1);
  });

  testWidgets('does not begin a swipe away from the thumb', (tester) async {
    var confirmations = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: RideConfirmationSlider(
                action: RidePrimaryAction.arriveAtPickup,
                onConfirmed: () => confirmations++,
              ),
            ),
          ),
        ),
      ),
    );

    final slider = find.byType(RideConfirmationSlider);
    final nearEnd = tester.getTopLeft(slider) + const Offset(320, 29);
    final gesture = await tester.startGesture(nearEnd);
    await gesture.moveBy(const Offset(20, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(confirmations, 0);
  });
}
