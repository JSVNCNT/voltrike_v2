import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/fare_service.dart';
import '../../../data/repositories/fare_repository.dart';

final fareRepositoryProvider = Provider<FareRepository>(
  (ref) => FareRepository(),
);

/// The passenger booking flow reacts to fare edits published by the developer
/// admin. A fallback keeps early development projects usable before settings
/// are seeded.
final fareConfigurationProvider = StreamProvider<FareConfiguration>(
  (ref) => ref.watch(fareRepositoryProvider).watchConfiguration(),
);
