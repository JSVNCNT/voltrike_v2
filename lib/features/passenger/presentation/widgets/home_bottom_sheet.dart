import 'package:flutter/material.dart';

import '../../../ride/tracking/widgets/trip_sheet_handle.dart';
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
    required this.isExpanded,
    required this.onToggleExpanded,
    required this.pickup,
    required this.destination,
    this.additionalDestination,
    this.additionalDropoffEnabled = false,
    this.onPickupTap,
    this.onDestinationTap,
    this.onAddDropoff,
    this.onAdditionalDestinationTap,
    this.onRemoveAdditionalDropoff,
    this.onEditNote,
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
    this.additionalDropoffFare = '₱0.00',
    this.dropoffCount = 1,
    this.isOutsideToda = false,
    this.routeAdvisory = '',

    this.hasRoute = false,
  });

  final ScrollController scrollController;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;

  final VoidCallback? onPickupTap;
  final VoidCallback? onDestinationTap;
  final VoidCallback? onAddDropoff;
  final VoidCallback? onAdditionalDestinationTap;
  final VoidCallback? onRemoveAdditionalDropoff;
  final VoidCallback? onEditNote;
  final VoidCallback? onBookRide;

  final VoidCallback? onIncreasePassengers;
  final VoidCallback? onDecreasePassengers;
  final VoidCallback? onIncreaseBaggage;
  final VoidCallback? onDecreaseBaggage;

  final String pickup;
  final String destination;
  final String? additionalDestination;
  final bool additionalDropoffEnabled;

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
  final String additionalDropoffFare;
  final int dropoffCount;
  final bool isOutsideToda;
  final String routeAdvisory;

  final bool hasRoute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: theme.colorScheme.outline, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            TripSheetHandle(
              isExpanded: isExpanded,
              onPressed: onToggleExpanded,
              expandLabel: 'Show booking form',
              collapseLabel: 'Hide booking form',
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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

                    Text(
                      additionalDropoffEnabled ? 'Drop-off 1' : 'Destination',
                      style: theme.textTheme.labelLarge,
                    ),

                    const SizedBox(height: 8),

                    LocationSearchBar(
                      hintText: destination,
                      icon: Icons.location_on,
                      onTap: onDestinationTap,
                      trailing: onAddDropoff == null || additionalDropoffEnabled
                          ? null
                          : Semantics(
                              button: true,
                              label: 'Add a second drop-off',
                              child: IconButton.filled(
                                tooltip: 'Add second drop-off',
                                onPressed: onAddDropoff,
                                icon: const Icon(Icons.add, weight: 700),
                                style: IconButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primary,
                                  foregroundColor: theme.colorScheme.onPrimary,
                                ),
                              ),
                            ),
                    ),

                    if (additionalDropoffEnabled) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Final drop-off',
                              style: theme.textTheme.labelLarge,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: onRemoveAdditionalDropoff,
                            icon: const Icon(Icons.remove_circle_outline),
                            label: const Text('Remove'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LocationSearchBar(
                        hintText:
                            additionalDestination ?? 'Add final destination',
                        icon: Icons.flag_outlined,
                        onTap: onAdditionalDestinationTap,
                      ),
                    ],

                    if (hasRoute) ...[
                      const SizedBox(height: 28),

                      Text('Ride Summary', style: theme.textTheme.titleMedium),

                      const SizedBox(height: 12),

                      if (routeAdvisory.isNotEmpty) ...[
                        _RouteAdvisoryCard(message: routeAdvisory),
                        const SizedBox(height: 12),
                      ],

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
                        additionalDropoffFare: additionalDropoffFare,
                        dropoffCount: dropoffCount,
                        isOutsideToda: isOutsideToda,
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

                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: hasRoute ? onBookRide : null,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                            ),
                            child: const Text('Book Ride'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox.square(
                          dimension: 56,
                          child: IconButton.filledTonal(
                            tooltip: 'Add note for driver',
                            onPressed: onEditNote,
                            icon: const Icon(Icons.note_add_outlined),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteAdvisoryCard extends StatelessWidget {
  const _RouteAdvisoryCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: colors.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Route advisory',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.onTertiaryContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onTertiaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
