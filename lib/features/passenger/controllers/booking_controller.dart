import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/booking.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../core/services/booking_quote_service.dart';
import '../providers/booking_session_provider.dart';

/// ===========================================================================
/// Booking Controller
///
/// Creates passenger bookings and stores them in Firestore.
///
/// Returns the generated booking ID so the passenger app can
/// immediately begin listening for booking updates.
/// ===========================================================================
class BookingController extends StateNotifier<AsyncValue<void>> {
  BookingController({
    required BookingRepository bookingRepository,
    required AuthRepository authRepository,
  }) : _bookingRepository = bookingRepository,
       _authRepository = authRepository,
       super(const AsyncData(null));

  final BookingRepository _bookingRepository;

  final AuthRepository _authRepository;

  final Uuid _uuid = const Uuid();
  Booking? _retryBooking;
  String? _retryFingerprint;
  bool _previousCreationFailed = false;

  Future<BookingCreationResult> createBooking({
    required BookingSession session,
    required String pickupAddress,
    required String destinationAddress,
    required double pickupLatitude,
    required double pickupLongitude,
  }) async {
    state = const AsyncLoading();

    try {
      final firebaseUser = _authRepository.currentUser;

      if (firebaseUser == null) {
        throw Exception('No authenticated passenger.');
      }

      if (session.destination == null) {
        throw Exception('Destination not selected.');
      }

      final fingerprint = jsonEncode({
        'passengerId': firebaseUser.uid,
        'pickup': [pickupLatitude, pickupLongitude],
        'destination': [
          session.destination!.latitude,
          session.destination!.longitude,
        ],
        'pickupAddress': pickupAddress,
        'destinationAddress': destinationAddress,
        'distanceMeters': session.distanceMeters,
        'estimatedFare': session.estimatedFare,
        'additionalPassengers': session.additionalPassengers,
        'baggageCount': session.baggageCount,
        'isOutsideToda': session.isOutsideToda,
        'routePolicy': session.routePolicy.toMap(),
      });

      if (_previousCreationFailed && _retryBooking != null) {
        try {
          final active = await _bookingRepository.getActiveBookingForPassenger(
            firebaseUser.uid,
          );
          if (active != null) {
            _clearCreationRetry();
            state = const AsyncData(null);
            return BookingCreationResult.fromBooking(active);
          }
          if (_retryFingerprint != fingerprint) {
            _clearCreationRetry();
          }
        } catch (_) {
          if (_retryFingerprint != fingerprint) {
            throw StateError(
              'The previous booking result could not be verified. '
              'Check your connection and retry before changing the trip.',
            );
          }
        }
      }

      final booking =
          _retryBooking ??
          Booking(
            bookingId: _uuid.v4(),
            passengerId: firebaseUser.uid,
            passengerName:
                firebaseUser.displayName ?? firebaseUser.email ?? 'Passenger',
            passengerPhone: firebaseUser.phoneNumber,
            passengerPhotoUrl: firebaseUser.photoURL,
            driverId: null,
            pickup: LatLng(pickupLatitude, pickupLongitude),
            destination: session.destination!,
            pickupName: session.pickupName,
            destinationName: session.destinationName,
            pickupAddress: pickupAddress,
            destinationAddress: destinationAddress,
            distanceMeters: session.distanceMeters,
            estimatedFare: session.estimatedFare,
            additionalPassengers: session.additionalPassengers,
            baggageCount: session.baggageCount,
            isOutsideToda: session.isOutsideToda,
            routePolicy: session.routePolicy,
            status: BookingStatus.pending,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
      _retryBooking = booking;
      _retryFingerprint = fingerprint;
      final quoteToken = await _quoteTokenFor(session);

      final creationResult = await _bookingRepository.createBooking(
        booking,
        goQuoteToken: quoteToken,
      );

      _clearCreationRetry();
      state = const AsyncData(null);

      return creationResult;
    } catch (e, stackTrace) {
      _previousCreationFailed = _retryBooking != null;
      state = AsyncError(e, stackTrace);

      rethrow;
    }
  }

  void _clearCreationRetry() {
    _retryBooking = null;
    _retryFingerprint = null;
    _previousCreationFailed = false;
  }

  Future<String> _quoteTokenFor(BookingSession session) async {
    final existingToken = session.goQuoteToken.trim();
    final expiresAt = session.goQuoteExpiresAt;
    if (existingToken.isNotEmpty &&
        expiresAt != null &&
        expiresAt.isAfter(DateTime.now().add(const Duration(seconds: 5)))) {
      return existingToken;
    }

    final pickup = session.pickup;
    final destination = session.destination;
    if (pickup == null || destination == null) {
      throw StateError('Select pickup and destination before booking.');
    }
    final refreshed = await BookingQuoteService.instance.tryBookingQuote(
      pickup: pickup,
      destination: destination,
      additionalPassengers: session.additionalPassengers,
      baggageCount: session.baggageCount,
    );
    if (refreshed == null || refreshed.quoteToken.trim().isEmpty) {
      throw StateError('The route quote could not be refreshed. Try again.');
    }
    return refreshed.quoteToken;
  }

  //==========================================================================
  // Cancel Booking
  //==========================================================================

  Future<void> cancelBooking(
    String bookingId, {
    String reasonCode = 'cancelled_by_passenger',
    String? reasonDetail,
  }) async {
    state = const AsyncLoading();

    try {
      await _bookingRepository.cancelBooking(
        bookingId,
        reasonCode: reasonCode,
        reasonDetail: reasonDetail,
      );

      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);

      rethrow;
    }
  }
}
