import 'package:flutter/material.dart';

/// ===========================================================================
/// Passenger Information Card
///
/// Displays information about the passenger.
///
/// This widget is intentionally presentation-only.
/// Ride actions (Call, Message, Report) are handled by RideActionsCard.
/// ===========================================================================
class PassengerInformationCard extends StatelessWidget {
  const PassengerInformationCard({
    super.key,
    required this.passengerName,
    this.photoUrl,
  });

  /// Passenger's display name.
  final String passengerName;

  /// Optional passenger profile photo.
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundImage: photoUrl != null
                  ? NetworkImage(photoUrl!)
                  : null,
              child: photoUrl == null
                  ? const Icon(
                      Icons.person,
                      size: 32,
                    )
                  : null,
            ),

            const SizedBox(height: 12),

            Text(
              passengerName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              'Passenger',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}