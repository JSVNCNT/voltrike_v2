import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/places_service.dart';
import '../../../data/models/place_prediction.dart';

/// ===========================================================================
/// Places Search Provider
///
/// Handles Google Places autocomplete searches.
/// ===========================================================================
class PlacesSearchNotifier
    extends StateNotifier<AsyncValue<List<PlacePrediction>>> {
  PlacesSearchNotifier()
      : super(const AsyncData(<PlacePrediction>[]));

  Future<void> search(
    String query,
  ) async {
    if (query.trim().isEmpty) {
      state = const AsyncData(<PlacePrediction>[]);
      return;
    }

    state = const AsyncLoading();

    try {
      final results =
          await PlacesService.searchPlaces(
        query,
      );

      state = AsyncData(results);
    } catch (e, stackTrace) {
      state = AsyncError(
        e,
        stackTrace,
      );
    }
  }

  void clear() {
    state = const AsyncData(<PlacePrediction>[]);
  }
}

final placesSearchProvider =
    StateNotifierProvider<
        PlacesSearchNotifier,
        AsyncValue<List<PlacePrediction>>>(
  (ref) => PlacesSearchNotifier(),
);