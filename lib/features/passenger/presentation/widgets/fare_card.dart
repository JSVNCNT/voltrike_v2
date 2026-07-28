import 'package:flutter/material.dart';

/// ===========================================================================
/// Fare Card
///
/// Displays the estimated fare summary.
///
/// NOTE:
/// This widget ONLY displays fare information.
///
/// Fare calculation is handled by:
/// • FareService
/// • Admin-configured pricing
/// ===========================================================================
class FareCard extends StatelessWidget {
  const FareCard({
    super.key,
    this.estimatedFare = '₱0.00',
    this.baseFare = '₱0.00',
    this.distanceFare = '₱0.00',
    this.distance = '--',
    this.eta = '--',
    this.additionalPassengers = 0,
    this.additionalPassengerFee = '₱0.00',
    this.baggageFee = '₱0.00',
    this.boundarySurcharge = '₱0.00',
  });

  final String estimatedFare;
  final String baseFare;
  final String distanceFare;

  final String distance;

  final String eta;

  final int additionalPassengers;
  final String additionalPassengerFee;

  final String baggageFee;

  final String boundarySurcharge;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _FareRow(
              title: 'Estimated Fare',
              value: estimatedFare,
              isBold: true,
            ),

            const Divider(),

            _FareRow(title: 'Base fare', value: baseFare),

            _FareRow(title: 'Distance surcharge', value: distanceFare),

            _FareRow(title: 'Distance', value: distance),

            _FareRow(title: 'Estimated Time', value: eta),

            _FareRow(
              title: 'Additional riders',
              value: additionalPassengers.toString(),
            ),

            _FareRow(
              title: 'Additional passenger fee',
              value: additionalPassengerFee,
            ),

            _FareRow(title: 'Baggage Fee', value: baggageFee),

            _FareRow(title: 'Outside TODA Surcharge', value: boundarySurcharge),

            const SizedBox(height: 8),
            Text(
              'Fare = base fare + distance surcharge + selected passenger, '
              'baggage, and boundary charges.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _FareRow extends StatelessWidget {
  const _FareRow({
    required this.title,
    required this.value,
    this.isBold = false,
  });

  final String title;

  final String value;

  final bool isBold;

  @override
  Widget build(BuildContext context) {
    final TextStyle? textStyle = isBold
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(title, style: textStyle)),
          Text(value, style: textStyle),
        ],
      ),
    );
  }
}
