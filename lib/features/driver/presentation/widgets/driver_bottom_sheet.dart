import 'package:flutter/material.dart';

/// ===========================================================================
/// Driver Bottom Sheet
///
/// Main control panel for the driver.
///
/// States:
/// • Offline
/// • Online (waiting)
/// • Booking Request
/// • Active Trip
/// ===========================================================================
class DriverBottomSheet extends StatelessWidget {
  const DriverBottomSheet({
    super.key,
    required this.isOnline,
    this.passengerName,
    this.pickupAddress,
    this.destinationAddress,
    this.estimatedFare,
    this.distance,
    this.onOnlineChanged,
    this.onAcceptBooking,
    this.onDeclineBooking,
    this.onNavigate,
    this.onArrived,
    this.onStartTrip,
    this.onCompleteTrip,
  });

  final bool isOnline;

  final String? passengerName;
  final String? pickupAddress;
  final String? destinationAddress;
  final String? estimatedFare;
  final String? distance;

  final ValueChanged<bool>? onOnlineChanged;

  final VoidCallback? onAcceptBooking;
  final VoidCallback? onDeclineBooking;
  final VoidCallback? onNavigate;
  final VoidCallback? onArrived;
  final VoidCallback? onStartTrip;
  final VoidCallback? onCompleteTrip;

  @override
  Widget build(BuildContext context) {
    final hasBooking =
        passengerName != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration:
                    BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius:
                      BorderRadius.circular(
                    99,
                  ),
                ),
              ),
            ),

            const SizedBox(
              height: 20,
            ),

            SwitchListTile(
              value: isOnline,
              onChanged:
                  onOnlineChanged,
              title: const Text(
                'Driver Online',
              ),
              subtitle: Text(
                isOnline
                    ? 'Receiving bookings'
                    : 'Offline',
              ),
            ),

            const SizedBox(
              height: 16,
            ),

            if (!hasBooking) ...[
              const Center(
                child: Padding(
                  padding:
                      EdgeInsets.symmetric(
                    vertical: 24,
                  ),
                  child: Text(
                    'Waiting for booking requests...',
                    style: TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            ] else ...[
              Text(
                passengerName!,
                style:
                    Theme.of(context)
                        .textTheme
                        .titleMedium,
              ),

              const SizedBox(
                height: 8,
              ),

              Text(
                'Pickup: ${pickupAddress ?? '--'}',
              ),

              Text(
                'Destination: ${destinationAddress ?? '--'}',
              ),

              const SizedBox(
                height: 8,
              ),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      estimatedFare ??
                          '--',
                    ),
                  ),
                  Expanded(
                    child: Text(
                      distance ??
                          '--',
                      textAlign:
                          TextAlign.end,
                    ),
                  ),
                ],
              ),

              const SizedBox(
                height: 20,
              ),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          onDeclineBooking,
                      child: const Text(
                        'Decline',
                      ),
                    ),
                  ),

                  const SizedBox(
                    width: 12,
                  ),

                  Expanded(
                    child:
                        ElevatedButton(
                      onPressed:
                          onAcceptBooking,
                      child: const Text(
                        'Accept',
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(
                height: 12,
              ),

              SizedBox(
                width:
                    double.infinity,
                child:
                    ElevatedButton(
                  onPressed:
                      onNavigate,
                  child: const Text(
                    'Navigate',
                  ),
                ),
              ),

              const SizedBox(
                height: 8,
              ),

              SizedBox(
                width:
                    double.infinity,
                child:
                    ElevatedButton(
                  onPressed:
                      onArrived,
                  child: const Text(
                    'Arrived',
                  ),
                ),
              ),

              const SizedBox(
                height: 8,
              ),

              SizedBox(
                width:
                    double.infinity,
                child:
                    ElevatedButton(
                  onPressed:
                      onStartTrip,
                  child: const Text(
                    'Start Trip',
                  ),
                ),
              ),

              const SizedBox(
                height: 8,
              ),

              SizedBox(
                width:
                    double.infinity,
                child:
                    FilledButton(
                  onPressed:
                      onCompleteTrip,
                  child: const Text(
                    'Complete Trip',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}