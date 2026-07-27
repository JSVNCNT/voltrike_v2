import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/booking_call_session.dart';

class BookingVoiceCallCredentials {
  const BookingVoiceCallCredentials({
    required this.serverUrl,
    required this.token,
    required this.callId,
    required this.endsAt,
  });

  final String serverUrl;
  final String token;
  final String callId;
  final DateTime endsAt;
}

/// Coordinates the server-authoritative booking call lifecycle. The LiveKit
/// API secret remains exclusively in Cloud Functions.
class BookingVoiceCallRepository {
  BookingVoiceCallRepository({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  }) : _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-southeast1'),
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;

  Stream<BookingCallSession?> watchCall(String bookingId) {
    return _firestore.collection('bookingCalls').doc(bookingId).snapshots().map(
      (snapshot) {
        if (!snapshot.exists) return null;
        final session = BookingCallSession.fromFirestore(snapshot);
        return session.callId.isEmpty ? null : session;
      },
    );
  }

  /// FCM alerts the user quickly; this listener is the durable source of truth
  /// when a push is delayed, denied, or the app resumes independently.
  Stream<BookingCallSession?> watchIncomingCall(String userId) {
    return _firestore
        .collection('bookingCalls')
        .where('recipientId', isEqualTo: userId)
        .where('status', isEqualTo: 'ringing')
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .orderBy('expiresAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) return null;
          final session = BookingCallSession.fromFirestore(snapshot.docs.first);
          return session.callId.isEmpty ? null : session;
        });
  }

  Future<BookingCallSession> startCall(String bookingId) async {
    final result = await _functions
        .httpsCallable('startBookingCall')
        .call<Map<Object?, Object?>>({'bookingId': bookingId});
    return _sessionFromCallable(result.data);
  }

  Future<BookingCallSession> respondCall({
    required String bookingId,
    required String callId,
    required BookingCallStatus response,
  }) async {
    if (![
      BookingCallStatus.accepted,
      BookingCallStatus.declined,
      BookingCallStatus.expired,
    ].contains(response)) {
      throw ArgumentError.value(response, 'response');
    }
    final result = await _functions
        .httpsCallable('respondBookingCall')
        .call<Map<Object?, Object?>>({
          'bookingId': bookingId,
          'callId': callId,
          'response': response.name,
        });
    return _sessionFromCallable(result.data);
  }

  Future<BookingVoiceCallCredentials> createCredentials({
    required String bookingId,
    required String callId,
  }) async {
    final result = await _functions
        .httpsCallable('createBookingCallToken')
        .call<Map<Object?, Object?>>({
          'bookingId': bookingId,
          'callId': callId,
        });
    final data = result.data;
    final serverUrl = data['serverUrl'] as String?;
    final token = data['token'] as String?;
    final returnedCallId = data['callId'] as String?;
    final endsAtMillis = _int(data['endsAtMillis']);
    if (serverUrl == null ||
        token == null ||
        returnedCallId == null ||
        endsAtMillis == null) {
      throw StateError('Voice service returned incomplete call credentials.');
    }
    return BookingVoiceCallCredentials(
      serverUrl: serverUrl,
      token: token,
      callId: returnedCallId,
      endsAt: DateTime.fromMillisecondsSinceEpoch(endsAtMillis),
    );
  }

  Future<void> endCall({
    required String bookingId,
    required String callId,
  }) async {
    await _functions.httpsCallable('endBookingCall').call<void>({
      'bookingId': bookingId,
      'callId': callId,
    });
  }

  BookingCallSession _sessionFromCallable(Map<Object?, Object?> data) {
    final bookingId = data['bookingId'] as String?;
    final callId = data['callId'] as String?;
    final callerId = data['callerId'] as String?;
    final recipientId = data['recipientId'] as String?;
    final expiresAtMillis = _int(data['expiresAtMillis']);
    if (bookingId == null ||
        callId == null ||
        callerId == null ||
        recipientId == null ||
        expiresAtMillis == null) {
      throw StateError('Voice service returned incomplete call state.');
    }
    return BookingCallSession.fromMap(
      bookingId: bookingId,
      data: {
        'bookingId': bookingId,
        'callId': callId,
        'callerId': callerId,
        'recipientId': recipientId,
        'status': data['status'],
        'createdAt': DateTime.now(),
        'expiresAt': expiresAtMillis,
        'endsAt': _int(data['endsAtMillis']),
      },
    );
  }

  static int? _int(Object? value) {
    return switch (value) {
      int number => number,
      num number => number.toInt(),
      _ => null,
    };
  }
}
