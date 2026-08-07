import 'dart:async';

import 'package:voltrike_v2/core/maps/voltrike_map.dart';

import '../../data/models/route_restriction.dart';
import '../native/route_restriction_engine.dart';
import 'polyline_service.dart';
import 'route_restriction_matcher.dart';
import 'voltrike_api.dart';

export 'route_restriction_matcher.dart';

/// Caches developer-controlled road and area restrictions for route selection.
class RouteRestrictionService {
  RouteRestrictionService._();

  static final RouteRestrictionService instance = RouteRestrictionService._();
  final VoltrikeApi _api = VoltrikeApi.instance;
  List<RouteRestriction>? _cache;
  DateTime? _loadedAt;
  RouteRestriction? _lastConflict;

  RouteRestriction? get lastConflict => _lastConflict;

  Future<List<RouteRestriction>> activeRestrictions({
    bool forceRefresh = false,
  }) async {
    if (_cache != null &&
        _loadedAt != null &&
        !forceRefresh &&
        DateTime.now().difference(_loadedAt!) < const Duration(seconds: 30)) {
      return _cache!;
    }
    final response = await _api.operation(
      'listActiveRouteRestrictions',
      const <String, dynamic>{},
    );
    final items = response['items'];
    _cache = items is Iterable
        ? items
              .whereType<Map>()
              .map(_restrictionFromApi)
              .toList(growable: false)
        : const <RouteRestriction>[];
    _loadedAt = DateTime.now();
    return _cache!;
  }

  /// Live active restrictions for maps. Callers still filter through the shared
  /// matcher so legacy, non-enforced corridor records never become overlays.
  /// The authenticated Go API is polled rather than reading Firestore directly.
  Stream<List<RouteRestriction>> watchActiveRestrictions() async* {
    var firstAttempt = true;
    while (true) {
      if (!firstAttempt) {
        await Future<void>.delayed(const Duration(seconds: 30));
      }
      try {
        yield List<RouteRestriction>.unmodifiable(
          await activeRestrictions(forceRefresh: !firstAttempt),
        );
      } catch (_) {
        // A transient refresh failure must not permanently terminate safety
        // monitoring. Keep the last known rules and retry on the next cycle.
        final cached = _cache;
        if (cached != null) {
          yield List<RouteRestriction>.unmodifiable(cached);
        }
      }
      firstAttempt = false;
    }
  }

  RouteRestriction _restrictionFromApi(Map<dynamic, dynamic> raw) {
    final data = raw.map((key, value) => MapEntry(key.toString(), value));
    return RouteRestriction.fromMap(
      id: (data['id'] as String?)?.trim() ?? '',
      data: data,
    );
  }

  void invalidate() {
    _cache = null;
    _loadedAt = null;
  }

  void markConflict(RouteRestriction restriction) {
    _lastConflict = restriction;
  }

  void clearLastConflict() => _lastConflict = null;

  Future<RouteRestriction?> routeConflict(List<LatLng> route) async {
    final restrictions = await activeRestrictions();
    final conflictIndex = await RouteRestrictionEngine.instance
        .firstRouteConflictIndex(route: route, restrictions: restrictions);
    if (conflictIndex != null) {
      final restriction = restrictions[conflictIndex];
      _lastConflict = restriction;
      return restriction;
    }
    return null;
  }

  Future<RouteRestriction?> encodedRouteConflict(String encodedPolyline) async {
    final restrictions = await activeRestrictions();
    final conflictIndex = await RouteRestrictionEngine.instance
        .firstEncodedRouteConflictIndex(
          encodedPolyline: encodedPolyline,
          restrictions: restrictions,
        );
    if (conflictIndex != null) {
      final restriction = restrictions[conflictIndex];
      _lastConflict = restriction;
      return restriction;
    }
    return null;
  }

  /// Highway corridor checks deliberately stay in Dart until the Rust bridge
  /// supports direction-and-distance semantics. The native engine continues
  /// to handle the hard MultiPolygon checks above.
  Future<HighwayTravelMatch?> encodedHighwayTravelConflict(
    String encodedPolyline,
  ) async {
    final restrictions = await activeRestrictions();
    final route = PolylineService.decodePolyline(encodedPolyline);
    return RouteRestrictionMatcher.firstHighwayTravelConflict(
      route,
      restrictions,
    );
  }

  Future<RouteRestriction?> pointConflict(LatLng point) async {
    final restrictions = await activeRestrictions();
    for (final restriction in restrictions) {
      if (RouteRestrictionMatcher.pointConflicts(point, restriction)) {
        _lastConflict = restriction;
        return restriction;
      }
    }
    return null;
  }

  Future<RouteRestriction?> bookingEndpointConflict(LatLng point) async {
    final restrictions = await activeRestrictions();
    for (final restriction in restrictions) {
      if (RouteRestrictionMatcher.isEnforcedPolygon(restriction) &&
          RouteRestrictionMatcher.pointConflicts(point, restriction)) {
        _lastConflict = restriction;
        return restriction;
      }
    }
    return null;
  }
}
