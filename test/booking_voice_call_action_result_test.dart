import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/data/models/booking_call_session.dart';
import 'package:voltrike_v2/data/repositories/booking_voice_call_repository.dart';

void main() {
  group('BookingVoiceCallActionResult', () {
    final now = DateTime.utc(2026, 7, 30, 2);
    final expiresAt = now.add(const Duration(seconds: 30));
    final endsAt = now.add(const Duration(minutes: 2));

    Map<Object?, Object?> callData({
      String status = 'ringing',
      String? serverUrl,
      String? token,
      int? endsAtMillis,
    }) {
      return {
        'bookingId': 'booking_12345678',
        'callId': 'call_12345678',
        'callerId': 'passenger_123',
        'recipientId': 'driver_123',
        'status': status,
        'expiresAtMillis': expiresAt.millisecondsSinceEpoch,
        'endsAtMillis': ?endsAtMillis,
        'serverUrl': ?serverUrl,
        'token': ?token,
      };
    }

    test('keeps a prewarm URL separate from persisted call state', () {
      final result = BookingVoiceCallActionResult.fromCallableData(
        callData(serverUrl: 'wss://example.livekit.cloud'),
      );

      expect(result.session.status, BookingCallStatus.ringing);
      expect(result.serverUrl, 'wss://example.livekit.cloud');
      expect(result.credentials, isNull);
    });

    test('parses ephemeral accepted-call credentials', () {
      final result = BookingVoiceCallActionResult.fromCallableData(
        callData(
          status: 'accepted',
          serverUrl: 'wss://example.livekit.cloud',
          token: 'short-lived-token',
          endsAtMillis: endsAt.millisecondsSinceEpoch,
        ),
      );

      expect(result.session.status, BookingCallStatus.accepted);
      expect(
        result.session.endsAt?.millisecondsSinceEpoch,
        endsAt.millisecondsSinceEpoch,
      );
      expect(result.credentials?.token, 'short-lived-token');
      expect(
        result.credentials?.isUsableFor(
          'call_12345678',
          endsAt.subtract(const Duration(milliseconds: 1)),
        ),
        isTrue,
      );
      expect(result.credentials?.isUsableFor('call_12345678', endsAt), isFalse);
      expect(result.credentials?.isUsableFor('different_call', now), isFalse);
    });

    test('rejects a partial credential response', () {
      expect(
        () => BookingVoiceCallActionResult.fromCallableData(
          callData(status: 'accepted', token: 'token-without-url-or-deadline'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects incomplete authoritative call identity', () {
      final data = callData()..remove('recipientId');
      expect(
        () => BookingVoiceCallActionResult.fromCallableData(data),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('BookingCallSession participant direction', () {
    final now = DateTime.utc(2026, 8, 8, 3);
    late BookingCallSession session;

    setUp(() {
      session = BookingCallSession.fromMap(
        bookingId: 'booking_trip_a',
        data: {
          'callId': 'call_trip_a',
          'callerId': 'passenger_a',
          'recipientId': 'driver_a',
          'status': 'ringing',
          'createdAt': now,
          'expiresAt': now.add(const Duration(seconds: 30)),
        },
      );
    });

    test('only recipient gets incoming call UI and ringtone', () {
      expect(
        session.isIncomingFor(
          'driver_a',
          expectedCallId: 'call_trip_a',
          at: now,
        ),
        isTrue,
      );
      expect(
        session.isIncomingFor(
          'passenger_a',
          expectedCallId: 'call_trip_a',
          at: now,
        ),
        isFalse,
      );
    });

    test('rejects another trip call and expired invitations', () {
      expect(
        session.isIncomingFor(
          'driver_a',
          expectedCallId: 'call_trip_b',
          at: now,
        ),
        isFalse,
      );
      expect(
        session.isIncomingFor(
          'driver_a',
          expectedCallId: 'call_trip_a',
          at: now.add(const Duration(seconds: 31)),
        ),
        isFalse,
      );
      expect(session.includesParticipant('unrelated_user'), isFalse);
    });

    test('accepted snapshot remains addressed to the recipient', () {
      final accepted = BookingCallSession.fromMap(
        bookingId: 'booking_trip_a',
        data: {
          'callId': 'call_trip_a',
          'callerId': 'passenger_a',
          'recipientId': 'driver_a',
          'status': 'accepted',
          'createdAt': now,
          'expiresAt': now.add(const Duration(seconds: 30)),
          'acceptedAt': now,
          'endsAt': now.add(const Duration(minutes: 30)),
        },
      );

      expect(
        accepted.isAddressedToRecipient(
          'driver_a',
          expectedCallId: 'call_trip_a',
        ),
        isTrue,
      );
      expect(
        accepted.isIncomingFor(
          'driver_a',
          expectedCallId: 'call_trip_a',
          at: now,
        ),
        isFalse,
      );
      expect(
        accepted.isAddressedToRecipient(
          'passenger_a',
          expectedCallId: 'call_trip_a',
        ),
        isFalse,
      );
    });
  });
}
