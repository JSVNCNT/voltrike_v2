import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/features/passenger/models/passenger_booking_policy.dart';

void main() {
  final now = DateTime.utc(2026, 10, 31, 10);

  test(
    'counts only rolling server timestamps and hides already appealed options',
    () {
      final policy = PassengerBookingPolicy.fromMap({
        'strikes': [
          {
            'bookingId': 'recent',
            'at': Timestamp.fromDate(now.subtract(const Duration(hours: 1))),
          },
          {
            'bookingId': 'appealed',
            'at': Timestamp.fromDate(now),
            'appealed': true,
          },
          {
            'bookingId': 'expired',
            'at': Timestamp.fromDate(now.subtract(const Duration(hours: 24))),
          },
          {
            'bookingId': 'future',
            'at': Timestamp.fromDate(now.add(const Duration(minutes: 1))),
          },
          {'bookingId': 'malformed'},
        ],
      }, now: now);
      expect(policy.strikes, ['recent', 'appealed']);
      expect(policy.appealableBookings, ['recent']);
    },
  );

  test('uses the later manual restriction and its explanation', () {
    final manual = now.add(const Duration(days: 3));
    final policy = PassengerBookingPolicy.fromMap({
      'blockedUntil': Timestamp.fromDate(now.add(const Duration(days: 1))),
      'manualBlockedUntil': Timestamp.fromDate(manual),
      'reason': 'Automatic restriction',
      'manualReason': 'Reviewed repeated misuse',
    }, now: now);
    expect(policy.blockedUntil!.isAtSameMomentAs(manual), isTrue);
    expect(policy.reason, 'Reviewed repeated misuse');
    expect(policy.canAppealRestriction, isTrue);
  });

  test(
    'active restriction remains appealable after an early strike ages out',
    () {
      final policy = PassengerBookingPolicy.fromMap({
        'blockedUntil': Timestamp.fromDate(now.add(const Duration(hours: 1))),
        'restrictionBookingIds': ['old-first', 'second', 'third'],
        'appealedBookingIds': ['second'],
      }, now: now);
      expect(policy.strikes, isEmpty);
      expect(policy.appealableBookings, ['old-first', 'third']);
    },
  );

  test('expired restrictions do not retain appeal actions', () {
    final policy = PassengerBookingPolicy.fromMap({
      'blockedUntil': Timestamp.fromDate(now),
      'manualBlockedUntil': Timestamp.fromDate(now),
      'restrictionBookingIds': ['old'],
    }, now: now);
    expect(policy.appealableBookings, isEmpty);
    expect(policy.canAppealRestriction, isFalse);
  });

  test('manual appeal stays pending without another submission button', () {
    final policy = PassengerBookingPolicy.fromMap({
      'manualBlockedUntil': Timestamp.fromDate(
        now.add(const Duration(days: 1)),
      ),
      'manualAppealStatus': 'pending',
    }, now: now);
    expect(policy.canAppealRestriction, isFalse);
    expect(policy.appealPending, isTrue);
  });

  test('empty or legacy policy imposes no restriction', () {
    final policy = PassengerBookingPolicy.fromMap({}, now: now);
    expect(policy.strikes, isEmpty);
    expect(policy.blockedUntil, isNull);
    expect(policy.notice, isEmpty);
  });
}
