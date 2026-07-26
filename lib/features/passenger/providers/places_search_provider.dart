import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/services/places_service.dart';
import '../../../data/models/place_prediction.dart';
import 'passenger_location_provider.dart';

/// ===========================================================================
/// Places Search Provider
///
/// Handles Google Places Autocomplete searches.
///
/// Automatically disposes when no longer used, so there is no need to
/// manually clear the search results.
/// ===========================================================================
class PlacesSearchNotifier
    extends StateNotifier<AsyncValue<List<PlacePrediction>>> {
  PlacesSearchNotifier(this._ref) : super(const AsyncData(<PlacePrediction>[]));

  final Ref _ref;
  Timer? _debounce;
  int _requestSequence = 0;

  /// Searches Google Places using the user's current location
  /// as a location bias when available.
  Future<void> search(
    String query, {
    LatLng? origin,
    String? sessionToken,
  }) async {
    final trimmedQuery = query.trim();
    _debounce?.cancel();
    final requestId = ++_requestSequence;

    if (trimmedQuery.isEmpty) {
      state = const AsyncData(<PlacePrediction>[]);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final passengerPosition = _ref.read(passengerLocationProvider).value;
      final latitude = origin?.latitude ?? passengerPosition?.latitude;
      final longitude = origin?.longitude ?? passengerPosition?.longitude;
      if (latitude == null || longitude == null) {
        if (requestId == _requestSequence) {
          state = AsyncError(
            StateError('Current location is required to search within 10 km.'),
            StackTrace.current,
          );
        }
        return;
      }
      state = const AsyncLoading();
      try {
        final results = await PlacesService.searchPlaces(
          trimmedQuery,
          latitude: latitude,
          longitude: longitude,
          sessionToken: sessionToken,
        );
        if (requestId == _requestSequence) state = AsyncData(results);
      } catch (error, stackTrace) {
        if (requestId == _requestSequence) {
          state = AsyncError(error, stackTrace);
        }
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

/// ===========================================================================
/// Places Search Provider
/// ===========================================================================
final placesSearchProvider =
    StateNotifierProvider.autoDispose<
      PlacesSearchNotifier,
      AsyncValue<List<PlacePrediction>>
    >((ref) => PlacesSearchNotifier(ref));
