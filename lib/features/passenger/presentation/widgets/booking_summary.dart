import 'package:flutter/material.dart';

class BookingSummary extends StatelessWidget {
  const BookingSummary({
    super.key,
    required this.pickup,
    required this.destination,
    required this.distance,
    required this.duration,
    required this.baseFare,
    required this.distanceFare,
    required this.additionalPassengerFee,
    required this.baggageFee,
    required this.boundaryFee,
    required this.totalFare,
  });

  final String pickup;
  final String destination;

  final String distance;
  final String duration;

  final double baseFare;
  final double distanceFare;
  final double additionalPassengerFee;
  final double baggageFee;
  final double boundaryFee;
  final double totalFare;

  Widget _fareRow(
    String title,
    double amount,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title),
          ),
          Text(
            '₱${amount.toStringAsFixed(2)}',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding:
            const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'Booking Summary',
              style: TextStyle(
                fontSize: 20,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              'Pickup',
              style: TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            Text(pickup),

            const SizedBox(height: 16),

            const Text(
              'Destination',
              style: TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            Text(destination),

            const Divider(height: 32),

            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Distance',
                  ),
                ),
                Text(distance),
              ],
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Duration',
                  ),
                ),
                Text(duration),
              ],
            ),

            const Divider(height: 32),

            const Text(
              'Fare Breakdown',
              style: TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            _fareRow(
              'Base Fare',
              baseFare,
            ),

            _fareRow(
              'Distance Fare',
              distanceFare,
            ),

            _fareRow(
              'Additional Passenger',
              additionalPassengerFee,
            ),

            _fareRow(
              'Baggage Fee',
              baggageFee,
            ),

            _fareRow(
              'Boundary Surcharge',
              boundaryFee,
            ),

            const Divider(),

            Row(
              children: [
                const Expanded(
                  child: Text(
                    'TOTAL',
                    style: TextStyle(
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                Text(
                  '₱${totalFare.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight:
                        FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}