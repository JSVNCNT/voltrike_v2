import 'package:flutter/material.dart';

import 'fare_card.dart';
import 'location_search_bar.dart';
import 'trip_options_card.dart';

/// ===========================================================================
/// Home Bottom Sheet
///
/// Booking Flow
/// • Pickup
/// • Destination
/// • Ride Summary
/// • Trip Options
/// • Book Ride
/// ===========================================================================
class HomeBottomSheet extends StatelessWidget {
  const HomeBottomSheet({
    super.key,
    required this.scrollController,
    required this.pickup,
    required this.destination,
    this.onPickupTap,
    this.onDestinationTap,
    this.onBookRide,

    this.onIncreasePassengers,
    this.onDecreasePassengers,
    this.onIncreaseBaggage,
    this.onDecreaseBaggage,

    this.estimatedFare = '₱0.00',
    this.baseFare = '₱0.00',
    this.distanceFare = '₱0.00',
    this.distance = '--',
    this.eta = '--',

    this.additionalPassengers = 0,
    this.baggageCount = 0,

    this.baggageFee = '₱0.00',
    this.additionalPassengerFee = '₱0.00',
    this.boundarySurcharge = '₱0.00',

    this.hasRoute = false,
  });

  final ScrollController scrollController;

  final VoidCallback? onPickupTap;
  final VoidCallback? onDestinationTap;
  final VoidCallback? onBookRide;

  final VoidCallback? onIncreasePassengers;
  final VoidCallback? onDecreasePassengers;
  final VoidCallback? onIncreaseBaggage;
  final VoidCallback? onDecreaseBaggage;

  final String pickup;
  final String destination;

  final String estimatedFare;
  final String baseFare;
  final String distanceFare;
  final String distance;
  final String eta;

  final int additionalPassengers;
  final int baggageCount;

  final String baggageFee;
  final String additionalPassengerFee;
  final String boundarySurcharge;

  final bool hasRoute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 10,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Text('Book a Ride', style: theme.textTheme.titleLarge),

              const SizedBox(height: 6),

              Text(
                hasRoute
                    ? 'Review your trip before booking.'
                    : 'Select your pickup and destination.',
                style: theme.textTheme.bodyMedium,
              ),

              const SizedBox(height: 24),

              Text('Pickup', style: theme.textTheme.labelLarge),

              const SizedBox(height: 8),

              LocationSearchBar(
                hintText: pickup,
                icon: Icons.my_location,
                onTap: onPickupTap,
              ),

              const SizedBox(height: 20),

              Text('Destination', style: theme.textTheme.labelLarge),

              const SizedBox(height: 8),

              LocationSearchBar(
                hintText: destination,
                icon: Icons.location_on,
                onTap: onDestinationTap,
              ),

              if (hasRoute) ...[
                const SizedBox(height: 28),

                Text('Ride Summary', style: theme.textTheme.titleMedium),

                const SizedBox(height: 12),

                FareCard(
                  estimatedFare: estimatedFare,
                  baseFare: baseFare,
                  distanceFare: distanceFare,
                  distance: distance,
                  eta: eta,
                  additionalPassengers: additionalPassengers,
                  additionalPassengerFee: additionalPassengerFee,
                  baggageFee: baggageFee,
                  boundarySurcharge: boundarySurcharge,
                ),

                const SizedBox(height: 16),

                TripOptionsCard(
                  additionalPassengers: additionalPassengers,
                  baggageCount: baggageCount,

                  onIncreasePassengers: onIncreasePassengers,
                  onDecreasePassengers: onDecreasePassengers,

                  onIncreaseBaggage: onIncreaseBaggage,
                  onDecreaseBaggage: onDecreaseBaggage,
                ),
              ],

              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: hasRoute ? onBookRide : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  child: const Text('Book Ride'),
                ),
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
