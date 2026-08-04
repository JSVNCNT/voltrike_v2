import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/route_restriction_service.dart';
import '../../data/models/route_restriction.dart';

/// Shared active restriction feed used by idle and route-preview map views.
final routeRestrictionsProvider = StreamProvider<List<RouteRestriction>>((ref) {
  return RouteRestrictionService.instance.watchActiveRestrictions();
});
