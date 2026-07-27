import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/features/ride/tracking/widgets/ride_actions_card.dart';

void main() {
  testWidgets('renders Material 3 ride actions and forwards every callback', (
    tester,
  ) async {
    var callCount = 0;
    var chatCount = 0;
    var reportCount = 0;
    var sosCount = 0;
    var cancelCount = 0;
    var noShowCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: RideActionsCard(
                onCall: () => callCount++,
                onMessage: () => chatCount++,
                onReport: () => reportCount++,
                onSos: () => sosCount++,
                onCancel: () => cancelCount++,
                onNoShow: () => noShowCount++,
                messageBadge: 3,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);
    expect(find.text('SOS'), findsOneWidget);
    expect(find.text('Cancel ride'), findsOneWidget);
    expect(find.text('No-show'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(Icons.assignment_late_outlined), findsOneWidget);
    expect(find.byIcon(Icons.sos_rounded), findsOneWidget);

    await tester.tap(find.text('Call'));
    await tester.tap(find.text('Chat'));
    await tester.tap(find.text('Report'));
    await tester.tap(find.text('SOS'));
    await tester.tap(find.text('Cancel ride'));
    await tester.tap(find.text('No-show'));

    expect(callCount, 1);
    expect(chatCount, 1);
    expect(reportCount, 1);
    expect(sosCount, 1);
    expect(cancelCount, 1);
    expect(noShowCount, 1);
  });

  testWidgets('does not render an empty action surface', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const Scaffold(body: RideActionsCard()),
      ),
    );

    expect(find.byType(Card), findsNothing);
  });
}
