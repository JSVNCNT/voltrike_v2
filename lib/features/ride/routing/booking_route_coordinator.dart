import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/booking.dart';
import 'booking_route_resolver.dart';

class BookingRouteCoordinator extends StatefulWidget {
  const BookingRouteCoordinator({
    super.key,
    required this.role,
    required this.booking,
    required this.redirectActiveBooking,
    required this.child,
  });

  final BookingParticipantRole role;
  final Booking? booking;
  final bool redirectActiveBooking;
  final Widget child;

  static void open(
    BuildContext context, {
    required BookingParticipantRole role,
    required Booking booking,
  }) {
    final decision = BookingRouteResolver.resolve(
      role: role,
      status: booking.status,
      bookingId: booking.bookingId,
    );
    context.go(decision.location, extra: decision.bookingId);
  }

  @override
  State<BookingRouteCoordinator> createState() =>
      _BookingRouteCoordinatorState();
}

class _BookingRouteCoordinatorState extends State<BookingRouteCoordinator> {
  String? _scheduledDecision;

  @override
  void initState() {
    super.initState();
    _scheduleRedirect();
  }

  @override
  void didUpdateWidget(covariant BookingRouteCoordinator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.booking?.bookingId != widget.booking?.bookingId ||
        oldWidget.booking?.status != widget.booking?.status ||
        oldWidget.redirectActiveBooking != widget.redirectActiveBooking) {
      _scheduleRedirect();
    }
  }

  void _scheduleRedirect() {
    final booking = widget.booking;
    if (!widget.redirectActiveBooking || booking == null) {
      _scheduledDecision = null;
      return;
    }

    final decision = BookingRouteResolver.resolve(
      role: widget.role,
      status: booking.status,
      bookingId: booking.bookingId,
    );
    final decisionKey =
        '${decision.location}:${decision.bookingId ?? ''}:${booking.status.name}';
    if (_scheduledDecision == decisionKey) return;
    _scheduledDecision = decisionKey;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _scheduledDecision != decisionKey) return;
      final currentLocation = GoRouterState.of(context).uri.path;
      if (currentLocation == decision.location) return;
      context.go(decision.location, extra: decision.bookingId);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
