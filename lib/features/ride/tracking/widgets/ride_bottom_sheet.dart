import 'package:flutter/material.dart';

import '../models/ride_action.dart';
import '../models/ride_status.dart';
import 'ride_information_card.dart';
import 'ride_primary_button.dart';
import 'ride_secondary_actions.dart';
import 'ride_status_card.dart';

class RideBottomSheet extends StatelessWidget {
  const RideBottomSheet({
    super.key,

    // Header
    required this.header,

    // Status
    required this.status,

    // Trip Information
    required this.pickupAddress,
    required this.destinationAddress,
    required this.estimatedFare,
    required this.distanceMeters,
    this.additionalPassengers,
    this.baggageCount,
    this.isOutsideToda,

    // Primary Action
    required this.primaryAction,
    required this.onPrimaryPressed,
    this.isLoading = false,

    // Secondary Actions
    this.onCall,
    this.onChat,
    this.onReport,
    this.onCancel,
  });

  /// DriverCard or PassengerCard
  final Widget header;

  /// Ride Status
  final RideStatus status;

  /// Trip Information
  final String pickupAddress;
  final String destinationAddress;
  final double estimatedFare;
  final int distanceMeters;

  final int? additionalPassengers;
  final int? baggageCount;
  final bool? isOutsideToda;

  /// Primary Action
  final RidePrimaryAction primaryAction;
  final VoidCallback? onPrimaryPressed;
  final bool isLoading;

  /// Secondary Actions
  final VoidCallback? onCall;
  final VoidCallback? onChat;
  final VoidCallback? onReport;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          16,
          12,
          16,
          24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,

            const SizedBox(height: 16),

            RideStatusCard(
              status: status,
            ),

            const SizedBox(height: 16),

            RideInformationCard(
              pickupAddress: pickupAddress,
              destinationAddress: destinationAddress,
              estimatedFare: estimatedFare,
              distanceMeters: distanceMeters,
              additionalPassengers: additionalPassengers,
              baggageCount: baggageCount,
              isOutsideToda: isOutsideToda,
            ),

            const SizedBox(height: 16),

            RideSecondaryActions(
              onCall: onCall,
              onChat: onChat,
              onReport: onReport,
              onCancel: onCancel,
            ),

            const SizedBox(height: 24),

            RidePrimaryButton(
              action: primaryAction,
              isLoading: isLoading,
              onPressed: onPrimaryPressed,
            ),
          ],
        ),
      ),
    );
  }
}