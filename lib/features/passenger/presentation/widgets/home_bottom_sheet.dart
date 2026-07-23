import 'package:flutter/material.dart';

import 'destination_search_bar.dart';
import 'fare_card.dart';

/// ===========================================================================
/// Home Bottom Sheet
///
/// Displays:
/// • Destination Search
/// • Fare Estimate
/// • ETA
/// • Distance
/// • Book Ride
/// ===========================================================================
class HomeBottomSheet extends StatelessWidget {
  const HomeBottomSheet({
    super.key,
    this.onDestinationTap,
    this.onBookRide,
    this.estimatedFare = '₱0.00',
    this.distance = '--',
    this.eta = '--',
    this.additionalPassengers = 0,
    this.baggageFee = '₱0.00',
    this.boundarySurcharge = '₱0.00',
    this.hasRoute = false,
  });

  final VoidCallback? onDestinationTap;
  final VoidCallback? onBookRide;

  final String estimatedFare;
  final String distance;
  final String eta;
  final int additionalPassengers;
  final String baggageFee;
  final String boundarySurcharge;

  /// True when a valid route has been computed.
  final bool hasRoute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(24),
          ),
          boxShadow: const [
            BoxShadow(
              blurRadius: 12,
              color: Colors.black12,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius:
                      BorderRadius.circular(100),
                ),
              ),
            ),

            const SizedBox(height: 20),

            Text(
              'Book a Ride',
              style: theme.textTheme.titleLarge,
            ),

            const SizedBox(height: 4),

            Text(
              hasRoute
                  ? 'Review your estimated fare below.'
                  : 'Choose your destination to begin.',
              style: theme.textTheme.bodyMedium,
            ),

            const SizedBox(height: 20),

            DestinationSearchBar(
              onTap: onDestinationTap,
            ),

            const SizedBox(height: 20),

            FareCard(
              estimatedFare: estimatedFare,
              distance: distance,
              eta: eta,
              additionalPassengers:
                  additionalPassengers,
              baggageFee: baggageFee,
              boundarySurcharge:
                  boundarySurcharge,
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    hasRoute ? onBookRide : null,
                style: FilledButton.styleFrom(
                  minimumSize:
                      const Size.fromHeight(54),
                ),
                child: const Text(
                  'Book Ride',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}