import 'package:cloud_firestore/cloud_firestore.dart';

enum BookingCallStatus {
  starting,
  ringing,
  accepted,
  declined,
  ended,
  expired;

  static BookingCallStatus parse(Object? value) {
    return switch (value) {
      'ringing' => BookingCallStatus.ringing,
      'accepted' => BookingCallStatus.accepted,
      'declined' => BookingCallStatus.declined,
      'ended' => BookingCallStatus.ended,
      'expired' => BookingCallStatus.expired,
      _ => BookingCallStatus.starting,
    };
  }

  bool get isTerminal =>
      this == BookingCallStatus.declined ||
      this == BookingCallStatus.ended ||
      this == BookingCallStatus.expired;
}

class BookingCallSession {
  const BookingCallSession({
    required this.bookingId,
    required this.callId,
    required this.callerId,
    required this.recipientId,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.acceptedAt,
    this.endsAt,
  });

  final String bookingId;
  final String callId;
  final String callerId;
  final String recipientId;
  final BookingCallStatus status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? acceptedAt;
  final DateTime? endsAt;

  factory BookingCallSession.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return BookingCallSession.fromMap(bookingId: snapshot.id, data: data);
  }

  factory BookingCallSession.fromMap({
    required String bookingId,
    required Map<String, dynamic> data,
  }) {
    return BookingCallSession(
      bookingId: _string(data['bookingId'], fallback: bookingId),
      callId: _string(data['callId']),
      callerId: _string(data['callerId']),
      recipientId: _string(data['recipientId']),
      status: BookingCallStatus.parse(data['status']),
      createdAt:
          _date(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      expiresAt:
          _date(data['expiresAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      acceptedAt: _date(data['acceptedAt']),
      endsAt: _date(data['endsAt']),
    );
  }

  BookingCallStatus effectiveStatus([DateTime? at]) {
    final now = at ?? DateTime.now();
    if (status == BookingCallStatus.ringing && !expiresAt.isAfter(now)) {
      return BookingCallStatus.expired;
    }
    if (status == BookingCallStatus.accepted &&
        endsAt != null &&
        !endsAt!.isAfter(now)) {
      return BookingCallStatus.ended;
    }
    return status;
  }

  Duration invitationRemaining([DateTime? at]) {
    final remaining = expiresAt.difference(at ?? DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Duration callRemaining([DateTime? at]) {
    final end = endsAt;
    if (end == null) return Duration.zero;
    final remaining = end.difference(at ?? DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Elapsed connected-call time for the call UI. The backend still owns
  /// [endsAt] and ends a call when it reaches its configured duration.
  Duration callElapsed([DateTime? at]) {
    final now = at ?? DateTime.now();
    final end = endsAt;
    final startedAt =
        acceptedAt ??
        (end == null ? createdAt : end.subtract(const Duration(minutes: 2)));
    final elapsed = now.difference(startedAt);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  bool matches(String expectedCallId) =>
      callId.isNotEmpty && callId == expectedCallId;

  bool includesParticipant(String userId) =>
      userId.isNotEmpty && (callerId == userId || recipientId == userId);

  bool isCaller(String userId) => userId.isNotEmpty && callerId == userId;

  bool isRecipient(String userId) =>
      userId.isNotEmpty && recipientId == userId && callerId != userId;

  /// Whether this call document belongs to the called participant and still
  /// represents the route's expected call. Unlike [isIncomingFor], this stays
  /// true after the recipient accepts, so an in-flight accept response cannot
  /// be mistaken for a stale or misdirected invitation.
  bool isAddressedToRecipient(String userId, {String? expectedCallId}) {
    return isRecipient(userId) &&
        (expectedCallId == null || matches(expectedCallId));
  }

  /// Incoming-call UI and ringtone are valid only for the called participant.
  /// This protects account-switched devices from stale FCM token delivery.
  bool isIncomingFor(String userId, {String? expectedCallId, DateTime? at}) {
    return isAddressedToRecipient(userId, expectedCallId: expectedCallId) &&
        effectiveStatus(at) == BookingCallStatus.ringing;
  }

  static String _string(Object? value, {String fallback = ''}) {
    return value is String && value.isNotEmpty ? value : fallback;
  }

  static DateTime? _date(Object? value) {
    return switch (value) {
      Timestamp timestamp => timestamp.toDate(),
      DateTime date => date,
      int milliseconds => DateTime.fromMillisecondsSinceEpoch(milliseconds),
      _ => null,
    };
  }
}
