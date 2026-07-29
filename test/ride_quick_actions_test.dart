import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/features/ride/tracking/widgets/ride_quick_actions.dart';

void main() {
  testWidgets('compact actions expose icon-only call and chat controls', (
    tester,
  ) async {
    var calls = 0;
    var chats = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RideQuickActions(
            onCall: () => calls++,
            onChat: () => chats++,
            messageBadge: 2,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.call_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
    expect(find.text('Call'), findsNothing);
    expect(find.text('Chat'), findsNothing);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.call_rounded));
    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));

    expect(calls, 1);
    expect(chats, 1);
  });

  testWidgets('safety actions use report and SOS controls', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RideQuickActions(onReport: () {}, onSos: () {}),
        ),
      ),
    );

    expect(find.byIcon(Icons.assignment_late_outlined), findsOneWidget);
    expect(find.byIcon(Icons.sos_rounded), findsOneWidget);
    expect(find.byIcon(Icons.call_rounded), findsNothing);
  });
}
