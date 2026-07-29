class RoutePolicyAdvisory {
  const RoutePolicyAdvisory({
    this.policyVersion = 'route_safety_v2',
    this.highwayAvoidanceRequested = true,
    this.restrictionsPartiallyIgnored = false,
    this.avoidedRestrictionNames = const [],
  });

  final String policyVersion;
  final bool highwayAvoidanceRequested;

  /// Google can set this when an avoidance preference could not be honoured.
  /// It is an advisory, not proof that the driver committed a violation.
  final bool restrictionsPartiallyIgnored;
  final List<String> avoidedRestrictionNames;

  bool get hasNotice =>
      restrictionsPartiallyIgnored || avoidedRestrictionNames.isNotEmpty;

  String get passengerMessage {
    if (restrictionsPartiallyIgnored) {
      return 'Highways are avoided where possible. Follow posted e-trike '
          'restrictions.';
    }
    if (avoidedRestrictionNames.isNotEmpty) {
      return 'Route adjusted to avoid ${avoidedRestrictionNames.join(', ')}.';
    }
    return '';
  }

  String get driverMessage {
    if (restrictionsPartiallyIgnored) {
      return 'Highway avoidance could not be fully confirmed. Follow posted '
          'e-trike restrictions and do not enter prohibited roads.';
    }
    if (avoidedRestrictionNames.isNotEmpty) {
      return 'Approved route avoids ${avoidedRestrictionNames.join(', ')}.';
    }
    return '';
  }

  Map<String, dynamic> toMap() {
    return {
      'policyVersion': policyVersion,
      'highwayAvoidanceRequested': highwayAvoidanceRequested,
      'routeRestrictionsPartiallyIgnored': restrictionsPartiallyIgnored,
      'avoidedRestrictionNames': avoidedRestrictionNames,
    };
  }

  factory RoutePolicyAdvisory.fromMap(Object? value) {
    final map = _map(value);
    return RoutePolicyAdvisory(
      policyVersion: _string(map['policyVersion']) ?? 'route_safety_v2',
      highwayAvoidanceRequested:
          _boolean(
            map['highwayAvoidanceRequested'] ?? map['requestedAvoidHighways'],
          ) ??
          true,
      restrictionsPartiallyIgnored:
          _boolean(
            map['routeRestrictionsPartiallyIgnored'] ??
                map['restrictionsPartiallyIgnored'],
          ) ??
          false,
      avoidedRestrictionNames: _strings(
        map['avoidedRestrictionNames'] ?? map['avoidedRouteRestrictionNames'],
      ),
    );
  }

  RoutePolicyAdvisory copyWith({
    bool? restrictionsPartiallyIgnored,
    List<String>? avoidedRestrictionNames,
  }) {
    return RoutePolicyAdvisory(
      policyVersion: policyVersion,
      highwayAvoidanceRequested: highwayAvoidanceRequested,
      restrictionsPartiallyIgnored:
          restrictionsPartiallyIgnored ?? this.restrictionsPartiallyIgnored,
      avoidedRestrictionNames:
          avoidedRestrictionNames ?? this.avoidedRestrictionNames,
    );
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, item) => MapEntry(key.toString(), item));
}

String? _string(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}

bool? _boolean(Object? value) {
  if (value is bool) return value;
  if (value is String) {
    if (value.toLowerCase() == 'true') return true;
    if (value.toLowerCase() == 'false') return false;
  }
  return null;
}

List<String> _strings(Object? value) {
  if (value is! Iterable) return const [];
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);
}
