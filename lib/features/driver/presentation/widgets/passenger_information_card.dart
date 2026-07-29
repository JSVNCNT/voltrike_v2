import 'package:flutter/material.dart';

/// ===========================================================================
/// Passenger Information Card
///
/// Displays information about the passenger.
///
/// This widget is intentionally presentation-only.
/// Compact ride actions may be placed beside the passenger identity.
/// ===========================================================================
class PassengerInformationCard extends StatelessWidget {
  const PassengerInformationCard({
    super.key,
    required this.passengerName,
    this.photoUrl,
    this.compact = false,
    this.actions,
  });

  /// Passenger's display name.
  final String passengerName;

  /// Optional passenger profile photo.
  final String? photoUrl;
  final bool compact;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasPhoto = photoUrl?.trim().isNotEmpty == true;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 27,
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.onPrimaryContainer,
              backgroundImage: hasPhoto ? NetworkImage(photoUrl!) : null,
              child: hasPhoto
                  ? null
                  : const Icon(Icons.person_rounded, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          passengerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.verified_user_outlined,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Confirmed ride passenger',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (actions != null) ...[
              const SizedBox(width: 8),
              actions!,
            ] else
              Icon(
                Icons.person_pin_circle_outlined,
                color: colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}
