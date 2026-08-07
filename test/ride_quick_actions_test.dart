import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/theme/app_colors.dart';
import 'package:voltrike_v2/features/common/presentation/widgets/adaptive_participant_name.dart';
import 'package:voltrike_v2/features/common/presentation/widgets/star_rating.dart';
import 'package:voltrike_v2/features/driver/presentation/widgets/passenger_information_card.dart';
import 'package:voltrike_v2/features/passenger/presentation/widgets/driver_information_card.dart';
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

    final callButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.call_rounded),
        matching: find.byType(IconButton),
      ),
    );
    final chatButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.chat_bubble_outline_rounded),
        matching: find.byType(IconButton),
      ),
    );
    expect(
      callButton.style?.backgroundColor?.resolve(const <WidgetState>{}),
      AppColors.callAction,
    );
    expect(
      chatButton.style?.backgroundColor?.resolve(const <WidgetState>{}),
      AppColors.chatAction,
    );

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

    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    expect(find.byIcon(Icons.sos_rounded), findsOneWidget);
    expect(find.byIcon(Icons.call_rounded), findsNothing);

    final reportButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.description_outlined),
        matching: find.byType(IconButton),
      ),
    );
    expect(
      reportButton.style?.backgroundColor?.resolve(const <WidgetState>{}),
      AppColors.reportAction,
    );
  });

  testWidgets('active SOS replaces SOS with teal safety status', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RideQuickActions(
            onReport: () {},
            onSos: () {},
            onSafetyUpdate: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    expect(find.byIcon(Icons.gpp_good_rounded), findsOneWidget);
    expect(find.byIcon(Icons.sos_rounded), findsNothing);

    final safetyButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.gpp_good_rounded),
        matching: find.byType(IconButton),
      ),
    );
    expect(
      safetyButton.style?.backgroundColor?.resolve(const <WidgetState>{}),
      AppColors.safetyAction,
    );
  });

  testWidgets('compact actions fit beside driver and passenger identities', (
    tester,
  ) async {
    final actions = RideQuickActions(onCall: () {}, onChat: () {});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: Column(
                children: [
                  DriverInformationCard(
                    driverName: 'A long responsive driver name',
                    vehicleNumber: 'E-Trike 12',
                    plateNumber: 'ABC-123',
                    todaName: 'Central TODA',
                    rating: 5,
                    compact: true,
                    actions: actions,
                  ),
                  PassengerInformationCard(
                    passengerName: 'A long responsive passenger name',
                    compact: true,
                    actions: actions,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(StarRating), findsOneWidget);
    expect(find.text('5.0'), findsOneWidget);
  });

  testWidgets('full participant names adapt on narrow phones', (tester) async {
    const driverName = 'Alexandria Montgomery Villanueva';
    const passengerName = 'Christopher Emmanuel Dela Cruz';
    final actions = RideQuickActions(onCall: () {}, onChat: () {});

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 280,
              child: Column(
                children: [
                  DriverInformationCard(
                    driverName: driverName,
                    vehicleNumber: 'E-Trike 12',
                    plateNumber: 'ABC-123',
                    todaName: 'Central TODA',
                    compact: true,
                    actions: actions,
                  ),
                  PassengerInformationCard(
                    passengerName: passengerName,
                    compact: true,
                    actions: actions,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text(driverName), findsOneWidget);
    expect(find.text(passengerName), findsOneWidget);
    expect(find.byType(AdaptiveParticipantName), findsNWidgets(2));

    for (final text in tester.widgetList<Text>(
      find.descendant(
        of: find.byType(AdaptiveParticipantName),
        matching: find.byType(Text),
      ),
    )) {
      expect(text.overflow, TextOverflow.visible);
      expect(text.style?.fontSize, greaterThanOrEqualTo(12));
    }
  });
}
