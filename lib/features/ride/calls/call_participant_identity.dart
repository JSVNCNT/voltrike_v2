import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../data/models/booking.dart';

class CallParticipantIdentity {
  const CallParticipantIdentity({
    required this.name,
    required this.roleLabel,
    this.photoUrl,
  });

  final String name;
  final String roleLabel;
  final String? photoUrl;

  factory CallParticipantIdentity.fromBooking({
    required Booking booking,
    required String? currentUserId,
  }) {
    if (currentUserId == booking.passengerId) {
      return CallParticipantIdentity(
        name: _name(booking.driverName, fallback: 'VolTrike driver'),
        roleLabel: 'Your driver',
        photoUrl: _photo(booking.driverPhotoUrl),
      );
    }
    if (currentUserId != null && currentUserId == booking.driverId) {
      return CallParticipantIdentity(
        name: _name(booking.passengerName, fallback: 'VolTrike passenger'),
        roleLabel: 'Your passenger',
        photoUrl: _photo(booking.passengerPhotoUrl),
      );
    }
    return const CallParticipantIdentity(
      name: 'Ride participant',
      roleLabel: 'Your current ride',
    );
  }

  String get initials {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'VP';
    if (words.length == 1) {
      return words.first.substring(0, 1).toUpperCase();
    }
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  static String _name(String? value, {required String fallback}) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? fallback : normalized;
  }

  static String? _photo(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

class CallParticipantAvatar extends StatelessWidget {
  const CallParticipantAvatar({
    super.key,
    required this.identity,
    this.radius = 76,
  });

  final CallParticipantIdentity identity;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: colors.primaryContainer,
      child: Center(
        child: Text(
          identity.initials,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            color: colors.onPrimaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );

    return Semantics(
      image: true,
      label: '${identity.name} profile photo',
      child: Container(
        width: radius * 2,
        height: radius * 2,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: .14),
          border: Border.all(
            color: Colors.white.withValues(alpha: .28),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: colors.primary.withValues(alpha: .24),
              blurRadius: 32,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipOval(
          child: identity.photoUrl == null
              ? fallback
              : CachedNetworkImage(
                  imageUrl: identity.photoUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => fallback,
                  errorWidget: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}
