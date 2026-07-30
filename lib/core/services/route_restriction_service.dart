import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';

import '../../data/models/route_restriction.dart';
import '../native/route_restriction_engine.dart';
import 'route_restriction_matcher.dart';

export 'route_restriction_matcher.dart';

/// Caches developer-controlled road and area restrictions for route selection.
class RouteRestrictionService {
  RouteRestrictionService._();

  static final RouteRestrictionService instance = RouteRestrictionService._();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<RouteRestriction>? _cache;
  DateTime? _loadedAt;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  RouteRestriction? _lastConflict;

  RouteRestriction? get lastConflict => _lastConflict;

  Future<List<RouteRestriction>> activeRestrictions() async {
    _ensureLiveUpdates();
    if (_cache != null &&
        _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(seconds: 30)) {
      return _cache!;
    }
    final snapshot = await _activeQuery.get();
    _replaceCache(snapshot);
    return _cache!;
  }

  Query<Map<String, dynamic>> get _activeQuery => _firestore
      .collection('routeRestrictions')
      .where('isActive', isEqualTo: true);

  void _ensureLiveUpdates() {
    _subscription ??= _activeQuery.snapshots().listen(
      _replaceCache,
      onError: (_) {
        // The bounded fetch above remains the fallback while Firestore
        // reconnects or the current account is not allowed to subscribe.
        _subscription = null;
      },
      onDone: () => _subscription = null,
      cancelOnError: true,
    );
  }

  void _replaceCache(QuerySnapshot<Map<String, dynamic>> snapshot) {
    _cache = snapshot.docs.map(RouteRestriction.fromFirestore).toList();
    _loadedAt = DateTime.now();
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
