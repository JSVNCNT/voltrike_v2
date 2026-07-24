import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  PlacesSearchNotifier(this._ref)
      : super(const AsyncData(<PlacePrediction>[]));

  final Ref _ref;

  /// Searches Google Places using the user's current location
  /// as a location bias when available.
  Future<void> search(String query) async {
    final trimmedQuery = query.trim();

    if (trimmedQuery.isEmpty) {
      state = const AsyncData(<PlacePrediction>[]);
      return;
    }

    state = const AsyncLoading();

    try {
      final location =
          _ref.read(passengerLocationProvider);

      final results =
          await PlacesService.searchPlaces(
        trimmedQuery,
        latitude: location.value?.latitude,
        longitude: location.value?.longitude,
      );

      state = AsyncData(results);
    } catch (error, stackTrace) {
      state = AsyncError(
        error,
        stackTrace,
      );
    }
  }
}

/// ===========================================================================
/// Places Search Provider
/// ===========================================================================
final placesSearchProvider =
    StateNotifierProvider.autoDispose<
        PlacesSearchNotifier,
        AsyncValue<List<PlacePrediction>>>(
  (ref) => PlacesSearchNotifier(ref),
);