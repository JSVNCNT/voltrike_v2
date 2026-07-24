import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voltrike_v2/data/models/place_prediction.dart';
import 'package:voltrike_v2/features/passenger/providers/places_search_provider.dart';
import 'package:voltrike_v2/features/passenger/presentation/widgets/place_tile.dart';

/// ===========================================================================
/// Location Search Screen
///
/// Used for:
/// • Pickup
/// • Destination
/// ===========================================================================
class DestinationSearchScreen extends ConsumerStatefulWidget {
  const DestinationSearchScreen({
    super.key,
    this.title = 'Choose Destination',
    this.hintText = 'Search destination',
  });

  final String title;
  final String hintText;

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

    _searchController = TextEditingController()
      ..addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    // Refresh the suffix icon when text changes.
    setState(() {});

    ref
        .read(placesSearchProvider.notifier)
        .search(_searchController.text);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchState =
        ref.watch(placesSearchProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction:
                  TextInputAction.search,
              decoration: InputDecoration(
                hintText: widget.hintText,
                prefixIcon:
                    const Icon(Icons.search),
                suffixIcon:
                    _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(
                              Icons.clear,
                            ),
                            onPressed: () {
                              _searchController.clear();

                              ref
                                  .read(
                                    placesSearchProvider
                                        .notifier,
                                  )
                                  .search('');
                            },
                          ),
                border:
                    const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: searchState.when(
              loading: () =>
                  const Center(
                child:
                    CircularProgressIndicator(),
              ),
              error: (error, _) =>
                  Center(
                child: Padding(
                  padding:
                      const EdgeInsets.all(24),
                  child: Text(
                    error.toString(),
                    textAlign:
                        TextAlign.center,
                  ),
                ),
              ),
              data: (
                List<PlacePrediction>
                    predictions,
              ) {
                if (_searchController.text
                    .trim()
                    .isEmpty) {
                  return Center(
                    child: Text(
                      widget.hintText,
                    ),
                  );
                }

                if (predictions.isEmpty) {
                  return const Center(
                    child: Text(
                      'No places found.',
                    ),
                  );
                }

                return ListView.separated(
                  itemCount:
                      predictions.length,
                  separatorBuilder:
                      (_, _) =>
                          const Divider(
                    height: 1,
                  ),
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
                        if (!mounted) {
                          return;
                        }

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