import 'dart:async';

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

    final thumb = find.byKey(const Key('ride-swipe-thumb'));
    await tester.drag(thumb, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(confirmations, 0);

    await tester.drag(thumb, const Offset(320, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(confirmations, 1);
  });

  testWidgets('ignores taps on the track', (tester) async {
    var confirmations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: RideConfirmationSlider(
              action: RidePrimaryAction.arriveAtPickup,
              onConfirmed: () => confirmations++,
            ),
          ),
        ),
      ),
    );

    final swipe = find.byType(RideConfirmationSlider);
    final nearEnd = tester.getTopRight(swipe) - const Offset(20, -30);
    await tester.tapAt(nearEnd);
    await tester.pumpAndSettle();

    expect(confirmations, 0);
  });

  testWidgets('uses concise action copy and follows the drag directly', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: RideConfirmationSlider(
              action: RidePrimaryAction.completeTrip,
              onConfirmed: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Swipe to confirm cash received'), findsOneWidget);

    final thumb = find.byKey(const Key('ride-swipe-thumb'));
    final startingLeft = tester.getTopLeft(thumb).dx;
    final gesture = await tester.startGesture(tester.getCenter(thumb));
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();

    expect(tester.getTopLeft(thumb).dx, closeTo(startingLeft + 120, 1));

    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(thumb).dx, closeTo(startingLeft, 1));
  });

  testWidgets('shows threshold, loading, and success feedback', (tester) async {
    final confirmation = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: RideConfirmationSlider(
              action: RidePrimaryAction.startTrip,
              onConfirmed: () => confirmation.future,
            ),
          ),
        ),
      ),
    );

    final thumb = find.byKey(const Key('ride-swipe-thumb'));
    final gesture = await tester.startGesture(tester.getCenter(thumb));
    await gesture.moveBy(const Offset(300, 0));
    await tester.pump();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await gesture.up();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Confirming...'), findsOneWidget);

    confirmation.complete();
    await tester.pump();
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
  });

  testWidgets('returns to a retry state when confirmation fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: RideConfirmationSlider(
              action: RidePrimaryAction.arriveAtPickup,
              onConfirmed: () => throw StateError('network unavailable'),
            ),
          ),
        ),
      ),
    );

    await tester.drag(
      find.byKey(const Key('ride-swipe-thumb')),
      const Offset(320, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('Update failed - swipe to retry'), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
  });
}
