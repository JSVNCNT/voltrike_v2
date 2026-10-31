import '../../../data/models/model_date_parser.dart';

class PassengerBookingPolicy {
  const PassengerBookingPolicy({
    this.strikes = const [],
    this.appealableBookings = const [],
    this.canAppealRestriction = false,
    this.appealPending = false,
    this.blockedUntil,
    this.reason = '',
  });

  final List<String> strikes;
  final List<String> appealableBookings;
  final bool canAppealRestriction;
  final bool appealPending;
  final DateTime? blockedUntil;
  final String reason;

  bool get isBlocked => blockedUntil?.isAfter(DateTime.now()) ?? false;

  factory PassengerBookingPolicy.fromMap(
    Map<String, dynamic> map, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final automatic = parseModelDate(map['blockedUntil']);
    final manual = parseModelDate(map['manualBlockedUntil']);
    final manualApplies =
        manual != null && (automatic == null || manual.isAfter(automatic));
    final strikes = <String>[];
    final appealable = <String>[];
    final appealed = List<String>.from(
      map['appealedBookingIds'] as List? ?? const [],
    );
    for (final raw in map['strikes'] as List? ?? const []) {
      if (raw is! Map) continue;
      final at = parseModelDate(raw['at']);
      final id = raw['bookingId'];
      if (at == null ||
          id is! String ||
          !at.isAfter(current.subtract(const Duration(hours: 24))) ||
          at.isAfter(current)) {
        continue;
      }
      strikes.add(id);
      if (raw['appealed'] != true && !appealed.contains(id)) appealable.add(id);
    }
    if (automatic?.isAfter(current) ?? false) {
      for (final id in List<String>.from(
        map['restrictionBookingIds'] as List? ?? const [],
      )) {
        if (!appealed.contains(id) && !appealable.contains(id)) {
          appealable.add(id);
        }
      }
    }
    return PassengerBookingPolicy(
      strikes: strikes,
      appealableBookings: appealable,
      canAppealRestriction:
          (manual?.isAfter(current) ?? false) &&
          map['manualAppealStatus'] != 'pending',
      appealPending:
          (map['disputedBookingIds'] as List? ?? const []).isNotEmpty ||
          map['manualAppealStatus'] == 'pending',
      blockedUntil: manualApplies ? manual : automatic,
      reason:
          (manualApplies ? map['manualReason'] : map['reason']) as String? ??
          '',
    );
  }

  String get notice {
    if (isBlocked) {
      final until = blockedUntil!.toLocal();
      final time =
          '${until.year}-${until.month.toString().padLeft(2, '0')}-'
          '${until.day.toString().padLeft(2, '0')} '
          '${until.hour.toString().padLeft(2, '0')}:'
          '${until.minute.toString().padLeft(2, '0')}';
      return 'New bookings are restricted until $time (local time). '
          '$reason Trip history, safety reports, and appeals remain available.';
    }
    if (strikes.length >= 2) {
      return 'You have ${strikes.length} qualifying cancellations in the last '
          '24 hours. Another will restrict new bookings for 24 hours.';
    }
    if (strikes.length == 1) {
      return 'Cancellation reminder: three qualifying cancellations within '
          '24 hours restrict new bookings for 24 hours.';
    }
    return appealPending
        ? 'Your cancellation appeal is pending System Admin review.'
        : '';
  }
}
