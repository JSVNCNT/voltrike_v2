import '../../data/models/route_restriction.dart';
import '../services/route_restriction_matcher.dart';
import '../theme/app_colors.dart';
import 'voltrike_map.dart';

/// One native polygon per stored area: stored areas are disconnected polygons,
/// not holes in a single polygon.
Set<Polygon> restrictionPolygons(Iterable<RouteRestriction> restrictions) {
  final polygons = <Polygon>{};
  for (final restriction in restrictions) {
    if (!RouteRestrictionMatcher.isEnforcedPolygon(restriction)) continue;
    for (var areaIndex = 0; areaIndex < restriction.areas.length; areaIndex++) {
      final area = restriction.areas[areaIndex];
      if (area.length < 3) continue;
      polygons.add(
        Polygon(
          polygonId: PolygonId('restriction:${restriction.id}:$areaIndex'),
          points: area,
          fillColor: AppColors.restrictedAreaFill,
          strokeColor: AppColors.restrictedAreaBorder,
          strokeWidth: 3,
          zIndex: 1,
        ),
      );
    }
  }
  return polygons;
}
