import 'package:flutter/material.dart';

import '../../../../data/models/booking.dart';

/// Driver controls are deliberately state-based: an incoming offer exposes
/// only Accept/Decline, while an active trip exposes only valid next steps.
class DriverBottomSheet extends StatelessWidget {
  const DriverBottomSheet({
    super.key,
    required this.isOnline,
    this.offerCooldownSeconds = 0,
    this.passengerName,
    this.pickupAddress,
    this.destinationAddress,
    this.estimatedFare,
    this.distance,
    this.bookingStatus,
    this.onOnlineChanged,
    this.onAcceptBooking,
    this.onDeclineBooking,
    this.onNavigate,
    this.onArrived,
    this.onStartTrip,
    this.onCompleteTrip,
    this.onCancelTrip,
  });

  final bool isOnline;
  final int offerCooldownSeconds;
  final String? passengerName;
  final String? pickupAddress;
  final String? destinationAddress;
  final String? estimatedFare;
  final String? distance;
  final BookingStatus? bookingStatus;
  final ValueChanged<bool>? onOnlineChanged;
  final VoidCallback? onAcceptBooking;
  final VoidCallback? onDeclineBooking;
  final VoidCallback? onNavigate;
  final VoidCallback? onArrived;
  final VoidCallback? onStartTrip;
  final VoidCallback? onCompleteTrip;
  final VoidCallback? onCancelTrip;

  @override
  Widget build(BuildContext context) {
    final isOffer = onAcceptBooking != null || onDeclineBooking != null;
    // Treat malformed legacy state as idle. The offer card is the only path
    // that may show a request before it is accepted; active-trip details need
    // both trusted addresses.
    final hasBooking =
        isOffer ||
        (bookingStatus != null &&
            passengerName?.trim().isNotEmpty == true &&
            _isUsableAddress(pickupAddress) &&
            _isUsableAddress(destinationAddress));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              value: isOnline,
              onChanged: onOnlineChanged,
              title: const Text('Driver Online'),
              subtitle: Text(isOnline ? 'Receiving bookings' : 'Offline'),
            ),
            const SizedBox(height: 16),
            if (!hasBooking)
              Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    offerCooldownSeconds > 0
                        ? 'New booking offers resume in $offerCooldownSeconds seconds.'
                        : 'Waiting for booking requests...',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else ...[
              Text(
                passengerName!,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text('Pickup: ${pickupAddress ?? '--'}'),
              Text('Destination: ${destinationAddress ?? '--'}'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text(estimatedFare ?? '--')),
                  Expanded(
                    child: Text(distance ?? '--', textAlign: TextAlign.end),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (isOffer)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onDeclineBooking,
                        child: const Text('Decline'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: onAcceptBooking,
                        child: const Text('Accept'),
                      ),
                    ),
                  ],
                )
              else
                _ActiveRideControls(
                  status: bookingStatus,
                  onNavigate: onNavigate,
                  onArrived: onArrived,
                  onStartTrip: onStartTrip,
                  onCompleteTrip: onCompleteTrip,
                  onCancelTrip: onCancelTrip,
                ),
            ],
          ],
        ),
      ),
    );
  }

  bool _isUsableAddress(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    return normalized.isNotEmpty &&
        normalized != '--' &&
        normalized != 'pickup location' &&
        normalized != 'destination';
  }
}

class _ActiveRideControls extends StatelessWidget {
  const _ActiveRideControls({
    required this.status,
    this.onNavigate,
    this.onArrived,
    this.onStartTrip,
    this.onCompleteTrip,
    this.onCancelTrip,
  });

  final BookingStatus? status;
  final VoidCallback? onNavigate;
  final VoidCallback? onArrived;
  final VoidCallback? onStartTrip;
  final VoidCallback? onCompleteTrip;
  final VoidCallback? onCancelTrip;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[];
    if (status == BookingStatus.driverAssigned) {
      actions.add(_button('Navigate', onNavigate));
      actions.add(_button('Arrived', onArrived));
    } else if (status == BookingStatus.driverArriving) {
      actions.add(_button('Start Trip', onStartTrip));
    } else if (status == BookingStatus.passengerOnBoard) {
      actions.add(_button('Drop Off Passenger', onCompleteTrip, filled: true));
    }
    if (status == BookingStatus.driverAssigned ||
        status == BookingStatus.driverArriving) {
      actions.add(_button('Cancel Trip', onCancelTrip, destructive: true));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < actions.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          actions[index],
        ],
      ],
    );
  }

  Widget _button(
    String label,
    VoidCallback? onPressed, {
    bool filled = false,
    bool destructive = false,
  }) {
    if (filled) return FilledButton(onPressed: onPressed, child: Text(label));
    return OutlinedButton(
      onPressed: onPressed,
      style: destructive
          ? OutlinedButton.styleFrom(foregroundColor: Colors.red)
          : null,
      child: Text(label),
    );
  }
}
