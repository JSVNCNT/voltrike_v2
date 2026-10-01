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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trip Options',
              style: Theme.of(context).textTheme.titleMedium,
            ),

            const SizedBox(height: 16),

            _OptionRow(
              label: 'Additional Passengers',
              helper:
                  '${additionalPassengers + 1} total rider'
                  '${additionalPassengers == 0 ? '' : 's'} • '
                  '${additionalPassengers + 1 <= 2 ? 'E-Trike Regular or E-Trike XL' : 'E-Trike XL required'}',
              value: additionalPassengers,
              maxValue: 3,
              onDecrease: onDecreasePassengers,
              onIncrease: onIncreasePassengers,
            ),

            const Divider(height: 32),

            _OptionRow(
              label: 'Baggage',
              helper: 'One baggage charge maximum',
              value: baggageCount,
              maxValue: 1,
              onDecrease: onDecreaseBaggage,
              onIncrease: onIncreaseBaggage,
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
    required this.maxValue,
    this.helper,
    this.onIncrease,
    this.onDecrease,
  });

  final String label;
  final int value;
  final int maxValue;
  final String? helper;

  final VoidCallback? onIncrease;
  final VoidCallback? onDecrease;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyLarge),
              if (helper != null)
                Text(helper!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),

        IconButton(
          onPressed: value > 0 ? onDecrease : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),

        SizedBox(
          width: 32,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),

        IconButton(
          onPressed: value < maxValue ? onIncrease : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}
