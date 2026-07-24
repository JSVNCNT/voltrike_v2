import 'package:flutter/material.dart';

/// ===========================================================================
/// Trip Options Card
///
/// Allows the passenger to configure:
/// • Additional passengers
/// • Baggage
///
/// These values affect the fare calculation.
/// ===========================================================================
class TripOptionsCard extends StatelessWidget {
  const TripOptionsCard({
    super.key,
    required this.additionalPassengers,
    required this.baggageCount,
    this.onIncreasePassengers,
    this.onDecreasePassengers,
    this.onIncreaseBaggage,
    this.onDecreaseBaggage,
  });

  final int additionalPassengers;
  final int baggageCount;

  final VoidCallback? onIncreasePassengers;
  final VoidCallback? onDecreasePassengers;

  final VoidCallback? onIncreaseBaggage;
  final VoidCallback? onDecreaseBaggage;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              'Trip Options',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium,
            ),

            const SizedBox(height: 16),

            _OptionRow(
              label: 'Additional Passengers',
              value: additionalPassengers,
              onDecrease:
                  onDecreasePassengers,
              onIncrease:
                  onIncreasePassengers,
            ),

            const Divider(height: 32),

            _OptionRow(
              label: 'Baggage',
              value: baggageCount,
              onDecrease:
                  onDecreaseBaggage,
              onIncrease:
                  onIncreaseBaggage,
            ),
          ],
        ),
      ),
    );
  }
}

/// ===========================================================================
/// Option Row
/// ===========================================================================
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.value,
    this.onIncrease,
    this.onDecrease,
  });

  final String label;
  final int value;

  final VoidCallback? onIncrease;
  final VoidCallback? onDecrease;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodyLarge,
          ),
        ),

        IconButton(
          onPressed:
              value > 0 ? onDecrease : null,
          icon: const Icon(
            Icons.remove_circle_outline,
          ),
        ),

        SizedBox(
          width: 32,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .titleMedium,
          ),
        ),

        IconButton(
          onPressed: onIncrease,
          icon: const Icon(
            Icons.add_circle_outline,
          ),
        ),
      ],
    );
  }
}