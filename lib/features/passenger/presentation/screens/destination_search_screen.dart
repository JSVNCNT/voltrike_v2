import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voltrike_v2/data/models/place_prediction.dart';
import 'package:voltrike_v2/features/passenger/providers/places_search_provider.dart';
import 'package:voltrike_v2/features/passenger/presentation/widgets/place_tile.dart';

/// ===========================================================================
/// Destination Search Screen
///
/// Searches destinations using the Google Places API.
/// ===========================================================================
class DestinationSearchScreen extends ConsumerStatefulWidget {
  const DestinationSearchScreen({
    super.key,
  });

  @override
  ConsumerState<DestinationSearchScreen> createState() =>
      _DestinationSearchScreenState();
}

class _DestinationSearchScreenState
    extends ConsumerState<DestinationSearchScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();

    _searchController = TextEditingController();

    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    ref
        .read(placesSearchProvider.notifier)
        .search(_searchController.text);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchState =
        ref.watch(placesSearchProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Choose Destination',
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search destination',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: searchState.when(
              loading: () => const Center(
                child:
                    CircularProgressIndicator(),
              ),
              error: (error, _) => Center(
                child: Text(
                  error.toString(),
                ),
              ),
              data: (
                List<PlacePrediction>
                    predictions,
              ) {
                if (predictions.isEmpty) {
                  return const Center(
                    child: Text(
                      'Search for a destination.',
                    ),
                  );
                }

                return ListView.builder(
                  itemCount:
                      predictions.length,
                  itemBuilder:
                      (context, index) {
                    final prediction =
                        predictions[index];

                    return PlaceTile(
                      title:
                          prediction.title,
                      subtitle:
                          prediction.subtitle ??
                              '',
                      onTap: () {
                        Navigator.of(context)
                            .pop(
                          prediction,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}