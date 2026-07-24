import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/booking.dart';

import '../../controllers/passenger_booking_flow_controller.dart';
import '../../providers/booking_controller_provider.dart';
import '../../providers/booking_listener_provider.dart';

import 'booking_tracking_screen.dart';
import 'rating_screen.dart';

/// ===========================================================================
/// Searching Driver Screen
///
/// Displays realtime booking updates while waiting for a driver.
///
/// Once a driver is assigned, navigation moves to
/// BookingTrackingScreen, which handles both:
///
/// • Driver → Pickup
/// • Driver → Destination
///
/// RatingScreen is shown after the booking is completed.
/// ===========================================================================
class SearchingDriverScreen extends ConsumerStatefulWidget {
  const SearchingDriverScreen({
    super.key,
    required this.bookingId,
  });

  final String bookingId;

  @override
  ConsumerState<SearchingDriverScreen> createState() =>
      _SearchingDriverScreenState();
}

class _SearchingDriverScreenState
    extends ConsumerState<SearchingDriverScreen> {
  BookingStatus? _lastStatus;

  ProviderSubscription<AsyncValue<Booking?>>?
      _bookingSubscription;

  //==========================================================================
  // Lifecycle
  //==========================================================================

  @override
  void initState() {
    super.initState();

    _bookingSubscription =
        ref.listenManual<AsyncValue<Booking?>>(
      bookingListenerProvider(
        widget.bookingId,
      ),
      (previous, next) {
        next.whenData((booking) {
          if (booking == null) {
            ref
                .read(
                  passengerBookingFlowProvider
                      .notifier,
                )
                .clear();
            return;
          }

          ref
              .read(
                passengerBookingFlowProvider
                    .notifier,
              )
              .updateStatus(
                booking.status,
              );

          _handleStatusChange(
            booking,
          );
        });
      },
    );
  }

  @override
  void dispose() {
    _bookingSubscription?.close();
    super.dispose();
  }

  //==========================================================================
  // Navigation
  //==========================================================================

  void _handleStatusChange(
    Booking booking,
  ) {
    if (_lastStatus ==
        booking.status) {
      return;
    }

    _lastStatus = booking.status;

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      switch (booking.status) {
        //--------------------------------------------------------------
        // Waiting
        //--------------------------------------------------------------

        case BookingStatus.pending:
          break;

        //--------------------------------------------------------------
        // Driver Assigned / Arriving
        //--------------------------------------------------------------

        case BookingStatus.driverAssigned:

        case BookingStatus.driverArriving:

        case BookingStatus.passengerOnBoard:
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => BookingTrackingScreen(
                bookingId: widget.bookingId,
              ),
            ),
          );
          break;

        //--------------------------------------------------------------
        // Completed
        //--------------------------------------------------------------

        case BookingStatus.completed:
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => RatingScreen(
                bookingId: widget.bookingId,
              ),
            ),
          );
          break;

        //--------------------------------------------------------------
        // Cancelled
        //--------------------------------------------------------------

        case BookingStatus.cancelled:
          Navigator.of(context).popUntil(
            (route) => route.isFirst,
          );
          break;
      }
    });
  }

  //==========================================================================
  // Build
  //==========================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final booking = ref.watch(
      bookingListenerProvider(
        widget.bookingId,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Searching Driver',
        ),
        automaticallyImplyLeading: false,
      ),
      body: booking.when(
         loading: () {
          return const Center(
            child: CircularProgressIndicator(),
          );
        },
        error: (error, _) {
          return Center(
            child: Text(
              error.toString(),
            ),
          );
        },
        data: (Booking? bookingData) {
          if (bookingData == null) {
            return const Center(
              child: Text(
                'Booking not found.',
              ),
            );
          }

          final status = bookingData.status;

          late final String title;
          late final String message;
          late final IconData icon;
          late final Color color;

          switch (status) {
            //--------------------------------------------------------------
            // Pending
            //--------------------------------------------------------------

            case BookingStatus.pending:
              title = 'Searching for nearby drivers';
              message =
                  'Please wait while we find an available driver.';
              icon = Icons.search;
              color = Colors.orange;
              break;

            //--------------------------------------------------------------
            // Driver Assigned
            //--------------------------------------------------------------

            case BookingStatus.driverAssigned:
              title = 'Driver Assigned';
              message =
                  'A driver has accepted your booking.';
              icon = Icons.person_pin_circle;
              color = Colors.blue;
              break;

            //--------------------------------------------------------------
            // Driver Arriving
            //--------------------------------------------------------------

            case BookingStatus.driverArriving:
              title = 'Driver Arriving';
              message =
                  'Your driver is on the way.';
              icon = Icons.directions_car;
              color = Colors.green;
              break;

            //--------------------------------------------------------------
            // Trip Started
            //--------------------------------------------------------------

            case BookingStatus.passengerOnBoard:
              title = 'Trip In Progress';
              message =
                  'Opening trip tracker...';
              icon = Icons.route;
              color = Colors.blueAccent;
              break;

            //--------------------------------------------------------------
            // Completed
            //--------------------------------------------------------------

            case BookingStatus.completed:
              title = 'Trip Completed';
              message =
                  'Preparing your trip summary...';
              icon = Icons.check_circle;
              color = Colors.green;
              break;

            //--------------------------------------------------------------
            // Cancelled
            //--------------------------------------------------------------

            case BookingStatus.cancelled:
              title = 'Booking Cancelled';
              message =
                  'This booking has been cancelled.';
              icon = Icons.cancel;
              color = Colors.red;
              break;
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(
                24,
              ),
              child: Column(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  if (status ==
                      BookingStatus.pending)
                    const CircularProgressIndicator()
                  else
                    Icon(
                      icon,
                      size: 80,
                      color: color,
                    ),

                  const SizedBox(
                    height: 32,
                  ),

                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const SizedBox(
                    height: 12,
                  ),

                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(
                    height: 24,
                  ),

                  Chip(
                    avatar: Icon(
                      icon,
                      size: 18,
                      color: Colors.white,
                    ),
                    backgroundColor: color,
                    label: Text(
                      status.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                  ),

                  const Spacer(),

                  if (status ==
                      BookingStatus.pending)
                    SizedBox(
                      width: double.infinity,
                      child:
                          OutlinedButton.icon(
                        onPressed: () async {
                          final messenger =
                              ScaffoldMessenger.of(
                            context,
                          );

                          final navigator =
                              Navigator.of(
                            context,
                          );

                          try {
                            await ref
                                .read(
                                  bookingControllerProvider
                                      .notifier,
                                )
                                .cancelBooking(
                                  widget.bookingId,
                                );

                            if (!mounted) {
                              return;
                            }

                            navigator.popUntil(
                              (route) =>
                                  route.isFirst,
                            );
                          } catch (e) {
                            if (!mounted) {
                              return;
                            }

                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Failed to cancel booking: $e',
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(
                          Icons.close,
                        ),
                        label: const Text(
                          'Cancel Booking',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}