import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/data/models/booking_call_session.dart';

void main() {
  group('BookingCallSession', () {
    final createdAt = DateTime.utc(2026, 7, 27, 1);
    final expiresAt = createdAt.add(const Duration(seconds: 30));
    final endsAt = createdAt.add(const Duration(minutes: 2));

    test('parses server timestamps and identity fields', () {
      final session = BookingCallSession.fromMap(
        bookingId: 'booking_12345678',
        data: {
          'callId': 'call_12345678',
          'callerId': 'passenger',
          'recipientId': 'driver',
          'status': 'accepted',
          'createdAt': Timestamp.fromDate(createdAt),
          'expiresAt': Timestamp.fromDate(expiresAt),
          'acceptedAt': Timestamp.fromDate(createdAt),
          'endsAt': Timestamp.fromDate(endsAt),
        },
      );

      expect(session.callId, 'call_12345678');
      expect(session.status, BookingCallStatus.accepted);
      expect(
        session.createdAt.millisecondsSinceEpoch,
        createdAt.millisecondsSinceEpoch,
      );
      expect(
        session.expiresAt.millisecondsSinceEpoch,
        expiresAt.millisecondsSinceEpoch,
      );
      expect(
        session.endsAt?.millisecondsSinceEpoch,
        endsAt.millisecondsSinceEpoch,
      );
    });

    test('derives exact invitation expiration from backend time', () {
      final session = BookingCallSession(
        bookingId: 'booking_12345678',
        callId: 'call_12345678',
        callerId: 'passenger',
        recipientId: 'driver',
        status: BookingCallStatus.ringing,
        createdAt: createdAt,
        expiresAt: expiresAt,
      );

      expect(
        session.effectiveStatus(
          expiresAt.subtract(const Duration(milliseconds: 1)),
        ),
        BookingCallStatus.ringing,
      );
      expect(session.effectiveStatus(expiresAt), BookingCallStatus.expired);
      expect(session.invitationRemaining(expiresAt), Duration.zero);
    });

    test('derives accepted-call end and rejects stale call IDs', () {
      final session = BookingCallSession(
        bookingId: 'booking_12345678',
        callId: 'call_current123',
        callerId: 'passenger',
        recipientId: 'driver',
        status: BookingCallStatus.accepted,
        createdAt: createdAt,
        expiresAt: expiresAt,
        acceptedAt: createdAt,
        endsAt: endsAt,
      );

      expect(session.matches('call_current123'), isTrue);
      expect(session.matches('call_stale1234'), isFalse);
      expect(session.effectiveStatus(endsAt), BookingCallStatus.ended);
      expect(session.callRemaining(endsAt), Duration.zero);
    });
  });
}
