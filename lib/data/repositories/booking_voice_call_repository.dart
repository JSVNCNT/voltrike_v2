import 'dart:async';

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

  bool isUsableFor(String expectedCallId, [DateTime? at]) {
    return callId == expectedCallId && endsAt.isAfter(at ?? DateTime.now());
  }
}

/// Ephemeral result returned by a call lifecycle callable.
///
/// Credentials are deliberately kept out of [BookingCallSession] because that
/// model also represents Firestore data. A token returned by a callable must
/// never be persisted in the booking-call document.
class BookingVoiceCallActionResult {
  const BookingVoiceCallActionResult({
    required this.session,
    this.serverUrl,
    this.credentials,
  });

  final BookingCallSession session;
  final String? serverUrl;
  final BookingVoiceCallCredentials? credentials;

  factory BookingVoiceCallActionResult.fromCallableData(
    Map<Object?, Object?> data,
  ) {
    final bookingId = _nonEmptyString(data['bookingId']);
    final callId = _nonEmptyString(data['callId']);
    final callerId = _nonEmptyString(data['callerId']);
    final recipientId = _nonEmptyString(data['recipientId']);
    final expiresAtMillis = _intValue(data['expiresAtMillis']);
    if (bookingId == null ||
        callId == null ||
        callerId == null ||
        recipientId == null ||
        expiresAtMillis == null) {
      throw StateError('Voice service returned incomplete call state.');
    }

    final endsAtMillis = _intValue(data['endsAtMillis']);
    final serverUrl = _nonEmptyString(data['serverUrl']);
    final token = _nonEmptyString(data['token']);
    BookingVoiceCallCredentials? credentials;
    if (token != null) {
      if (serverUrl == null || endsAtMillis == null) {
        throw StateError('Voice service returned incomplete call credentials.');
      }
      credentials = BookingVoiceCallCredentials(
        serverUrl: serverUrl,
        token: token,
        callId: callId,
        endsAt: DateTime.fromMillisecondsSinceEpoch(endsAtMillis),
      );
    }

    return BookingVoiceCallActionResult(
      session: BookingCallSession.fromMap(
        bookingId: bookingId,
        data: {
          'bookingId': bookingId,
          'callId': callId,
          'callerId': callerId,
          'recipientId': recipientId,
          'status': data['status'],
          'createdAt': DateTime.now(),
          'expiresAt': expiresAtMillis,
          'endsAt': endsAtMillis,
        },
      ),
      serverUrl: serverUrl,
      credentials: credentials,
    );
  }

  static String? _nonEmptyString(Object? value) {
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  static int? _intValue(Object? value) {
    return switch (value) {
      int number => number,
      num number => number.toInt(),
      _ => null,
    };
  }
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

  static const Duration _stateCallTimeout = Duration(seconds: 10);
  static const Duration _tokenCallTimeout = Duration(seconds: 10);
  static const Duration _endCallTimeout = Duration(seconds: 6);

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
    return (await startCallWithResult(bookingId)).session;
  }

  Future<BookingVoiceCallActionResult> startCallWithResult(
    String bookingId,
  ) async {
    final result = await _callWithOneRetry(
      () => _functions
          .httpsCallable('startBookingCall')
          .call<Map<Object?, Object?>>({'bookingId': bookingId}),
      timeout: _stateCallTimeout,
    );
    return BookingVoiceCallActionResult.fromCallableData(result.data);
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
    return (await respondCallWithResult(
      bookingId: bookingId,
      callId: callId,
      response: response,
    )).session;
  }

  Future<BookingVoiceCallActionResult> respondCallWithResult({
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
    final result = await _callWithOneRetry(
      () => _functions
          .httpsCallable('respondBookingCall')
          .call<Map<Object?, Object?>>({
            'bookingId': bookingId,
            'callId': callId,
            'response': response.name,
          }),
      timeout: _stateCallTimeout,
    );
    return BookingVoiceCallActionResult.fromCallableData(result.data);
  }

  Future<BookingVoiceCallCredentials> createCredentials({
    required String bookingId,
    required String callId,
  }) async {
    final result = await _callWithOneRetry(
      () => _functions
          .httpsCallable('createBookingCallToken')
          .call<Map<Object?, Object?>>({
            'bookingId': bookingId,
            'callId': callId,
          }),
      timeout: _tokenCallTimeout,
    );
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
    await _callWithOneRetry(
      () => _functions.httpsCallable('endBookingCall').call<void>({
        'bookingId': bookingId,
        'callId': callId,
      }),
      timeout: _endCallTimeout,
    );
  }

  Future<T> _callWithOneRetry<T>(
    Future<T> Function() operation, {
    required Duration timeout,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await operation().timeout(timeout);
      } catch (error) {
        if (attempt > 0 || !_isRetryable(error)) rethrow;
      }
    }
    throw StateError('Unreachable voice-call retry state.');
  }

  static bool _isRetryable(Object error) {
    if (error is TimeoutException) return true;
    return error is FirebaseFunctionsException &&
        (error.code == 'deadline-exceeded' || error.code == 'unavailable');
  }

  static int? _int(Object? value) {
    return switch (value) {
      int number => number,
      num number => number.toInt(),
      _ => null,
    };
  }
}
