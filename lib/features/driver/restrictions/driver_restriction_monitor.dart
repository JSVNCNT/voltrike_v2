import 'package:voltrike_v2/core/maps/voltrike_map.dart';

import '../../../core/services/route_restriction_service.dart';
import '../../../data/models/route_restriction.dart';

enum DriverRestrictionPhase { clear, approaching, inside }

class DriverRestrictionObservation {
  const DriverRestrictionObservation({
    required this.phase,
    this.restriction,
    this.distanceMeters = double.infinity,
  });

  final DriverRestrictionPhase phase;
  final RouteRestriction? restriction;
  final double distanceMeters;
}

class DriverRestrictionTransition {
  const DriverRestrictionTransition({
    required this.previous,
    required this.current,
    required this.shouldAlert,
  });

  final DriverRestrictionObservation previous;
  final DriverRestrictionObservation current;
  final bool shouldAlert;

  bool get entered =>
      current.phase == DriverRestrictionPhase.inside &&
      (previous.phase != DriverRestrictionPhase.inside ||
          previous.restriction?.id != current.restriction?.id);

  bool get exited =>
      previous.phase == DriverRestrictionPhase.inside &&
      (current.phase != DriverRestrictionPhase.inside ||
          previous.restriction?.id != current.restriction?.id);
}

/// Applies GPS-quality gates, two-sample confirmation, boundary hysteresis,
/// and transition cooldowns to developer-approved polygon restrictions.
///
/// Highway corridors are intentionally absent: a point-to-line match cannot
/// tell legal crossing from travelling along a prohibited road.
class DriverRestrictionTransitionEngine {
  DriverRestrictionTransitionEngine({
    this.approachDistanceMeters = 100,
    this.approachExitDistanceMeters = 130,
    this.insideExitDistanceMeters = 30,
    this.maximumAccuracyMeters = 35,
    this.maximumSampleAge = const Duration(seconds: 30),
    this.confirmationSamples = 2,
    this.alertCooldown = const Duration(minutes: 2),
  });

  final double approachDistanceMeters;
  final double approachExitDistanceMeters;
  final double insideExitDistanceMeters;
  final double maximumAccuracyMeters;
  final Duration maximumSampleAge;
  final int confirmationSamples;
  final Duration alertCooldown;

  DriverRestrictionObservation _current = const DriverRestrictionObservation(
    phase: DriverRestrictionPhase.clear,
  );
  DriverRestrictionObservation? _candidate;
  int _candidateSamples = 0;
  final Map<String, DateTime> _lastAlertAt = {};
  DateTime? _lastAcceptedObservedAt;

  DriverRestrictionObservation get current => _current;

  bool isSampleEligible({
    required double accuracyMeters,
    required DateTime observedAt,
    required DateTime now,
  }) {
    if (!accuracyMeters.isFinite ||
        accuracyMeters < 0 ||
        accuracyMeters > maximumAccuracyMeters) {
      return false;
    }
    final age = now.difference(observedAt);
    if (age > maximumSampleAge || age < const Duration(seconds: -10)) {
      return false;
    }
    final previousObservedAt = _lastAcceptedObservedAt;
    return previousObservedAt == null || observedAt.isAfter(previousObservedAt);
  }

  DriverRestrictionTransition? evaluate({
    required LatLng point,
    required double accuracyMeters,
    required DateTime observedAt,
    required DateTime now,
    required List<RouteRestriction> restrictions,
    RouteRestrictionProximity? proximity,
  }) {
    if (!isSampleEligible(
      accuracyMeters: accuracyMeters,
      observedAt: observedAt,
      now: now,
    )) {
      return null;
    }
    _lastAcceptedObservedAt = observedAt;

    final desired = _classify(point, restrictions, proximity);
    if (_sameTarget(desired, _current)) {
      _candidate = null;
      _candidateSamples = 0;
      _current = desired;
      return null;
    }

    if (_candidate != null && _sameTarget(desired, _candidate!)) {
      _candidateSamples++;
    } else {
      _candidate = desired;
      _candidateSamples = 1;
    }
    if (_candidateSamples < confirmationSamples) return null;

    final previous = _current;
    _current = desired;
    _candidate = null;
    _candidateSamples = 0;

    if (previous.phase == DriverRestrictionPhase.inside &&
        desired.phase != DriverRestrictionPhase.inside) {
      final previousId = previous.restriction?.id;
      if (previousId != null) {
        _lastAlertAt.remove(
          '$previousId:${DriverRestrictionPhase.inside.name}',
        );
      }
    }

    var shouldAlert = false;
    if (desired.phase != DriverRestrictionPhase.clear &&
        desired.restriction != null) {
      final key = '${desired.restriction!.id}:${desired.phase.name}';
      final lastAlert = _lastAlertAt[key];
      shouldAlert =
          lastAlert == null || now.difference(lastAlert) >= alertCooldown;
      if (shouldAlert) _lastAlertAt[key] = now;
    }
    return DriverRestrictionTransition(
      previous: previous,
      current: desired,
      shouldAlert: shouldAlert,
    );
  }

  void reset() {
    _current = const DriverRestrictionObservation(
      phase: DriverRestrictionPhase.clear,
    );
    _candidate = null;
    _candidateSamples = 0;
    _lastAlertAt.clear();
    _lastAcceptedObservedAt = null;
  }

  DriverRestrictionObservation _classify(
    LatLng point,
    List<RouteRestriction> restrictions,
    RouteRestrictionProximity? proximity,
  ) {
    final resolvedProximity =
        proximity ??
        RouteRestrictionMatcher.pointProximity(
          point,
          restrictions,
          preferredRestrictionId: _current.restriction?.id,
        );
    if (resolvedProximity.nearestRestrictionIndex == null) {
      return const DriverRestrictionObservation(
        phase: DriverRestrictionPhase.clear,
      );
    }

    final currentRestrictionId = _current.restriction?.id;
    if (currentRestrictionId != null) {
      final currentRestriction = restrictions
          .where(RouteRestrictionMatcher.isEnforcedPolygon)
          .where((item) => item.id == currentRestrictionId)
          .firstOrNull;
      if (currentRestriction != null) {
        final distance =
            resolvedProximity.preferredDistanceMeters ??
            RouteRestrictionMatcher.distanceToEnforcedPolygonMeters(
              point,
              currentRestriction,
            );
        if (_current.phase == DriverRestrictionPhase.inside &&
            distance <= insideExitDistanceMeters) {
          return DriverRestrictionObservation(
            phase: DriverRestrictionPhase.inside,
            restriction: currentRestriction,
            distanceMeters: distance,
          );
        }
        if (_current.phase == DriverRestrictionPhase.approaching &&
            distance > 0 &&
            distance <= approachExitDistanceMeters) {
          return DriverRestrictionObservation(
            phase: DriverRestrictionPhase.approaching,
            restriction: currentRestriction,
            distanceMeters: distance,
          );
        }
      }
    }

    final inside = _restrictionAt(
      restrictions,
      resolvedProximity.insideRestrictionIndex,
    );
    if (inside != null) {
      return DriverRestrictionObservation(
        phase: DriverRestrictionPhase.inside,
        restriction: inside,
        distanceMeters: 0,
      );
    }

    final closest = _restrictionAt(
      restrictions,
      resolvedProximity.nearestRestrictionIndex,
    );
    final closestDistance =
        resolvedProximity.nearestDistanceMeters ?? double.infinity;
    if (closest != null && closestDistance <= approachDistanceMeters) {
      return DriverRestrictionObservation(
        phase: DriverRestrictionPhase.approaching,
        restriction: closest,
        distanceMeters: closestDistance,
      );
    }
    return const DriverRestrictionObservation(
      phase: DriverRestrictionPhase.clear,
    );
  }

  RouteRestriction? _restrictionAt(
    List<RouteRestriction> restrictions,
    int? index,
  ) {
    if (index == null || index < 0 || index >= restrictions.length) return null;
    final restriction = restrictions[index];
    return RouteRestrictionMatcher.isEnforcedPolygon(restriction)
        ? restriction
        : null;
  }

  bool _sameTarget(
    DriverRestrictionObservation left,
    DriverRestrictionObservation right,
  ) {
    return left.phase == right.phase &&
        left.restriction?.id == right.restriction?.id;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
