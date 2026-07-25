import 'package:flutter/material.dart';

class RideInformationCard extends StatelessWidget {
  const RideInformationCard({
    super.key,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.estimatedFare,
    required this.distanceMeters,
    this.additionalPassengers,
    this.baggageCount,
    this.isOutsideToda,
  });

  final String pickupAddress;
  final String destinationAddress;
  final double estimatedFare;
  final int distanceMeters;

  final int? additionalPassengers;
  final int? baggageCount;
  final bool? isOutsideToda;

  @override
  Widget build(BuildContext context) {
    final _ = Theme.of(context);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _InfoTile(
              icon: Icons.my_location,
              title: 'Pickup',
              value: pickupAddress,
            ),

            const Divider(height: 24),

            _InfoTile(
              icon: Icons.location_on,
              title: 'Destination',
              value: destinationAddress,
            ),

            const Divider(height: 24),

            Row(
              children: [
                Expanded(
                  child: _StatisticTile(
                    label: 'Fare',
                    value: '₱${estimatedFare.toStringAsFixed(2)}',
                  ),
                ),
                Expanded(
                  child: _StatisticTile(
                    label: 'Distance',
                    value: _formatDistance(distanceMeters),
                  ),
                ),
              ],
            ),

            if (additionalPassengers != null ||
                baggageCount != null ||
                isOutsideToda != null) ...[
              const Divider(height: 24),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (additionalPassengers != null)
                    Chip(
                      avatar: const Icon(Icons.people, size: 18),
                      label: Text(
                        '$additionalPassengers Passenger(s)',
                      ),
                    ),

                  if (baggageCount != null)
                    Chip(
                      avatar: const Icon(Icons.luggage, size: 18),
                      label: Text(
                        '$baggageCount Baggage',
                      ),
                    ),

                  if (isOutsideToda == true)
                    const Chip(
                      avatar: Icon(Icons.warning_amber_rounded, size: 18),
                      label: Text('Outside TODA'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDistance(int meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }

    return '$meters m';
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatisticTile extends StatelessWidget {
  const _StatisticTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}