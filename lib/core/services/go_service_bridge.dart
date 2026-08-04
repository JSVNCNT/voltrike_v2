import 'package:cloud_functions/cloud_functions.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';

import '../../data/models/route_policy_advisory.dart';

typedef GoQuoteCallable = Future<Object?> Function(Map<String, dynamic> input);

class GoQuoteException implements Exception {
  const GoQuoteException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GoBookingQuote {
  const GoBookingQuote({
    required this.distanceMeters,
    required this.estimatedFare,
    required this.estimatedDuration,
    required this.encodedPolyline,
    required this.fareBreakdown,
    required this.fareVersion,
    required this.isOutsideToda,
    required this.coverageClass,
    required this.routePolicy,
    required this.quoteToken,
    this.quoteExpiresAt,
  });

  final int distanceMeters;
  final double estimatedFare;
  final String estimatedDuration;
  final String encodedPolyline;
  final Map<String, dynamic> fareBreakdown;
  final int fareVersion;
  final bool isOutsideToda;
  final String coverageClass;
  final RoutePolicyAdvisory routePolicy;
  final String quoteToken;
  final DateTime? quoteExpiresAt;

  int? get durationMinutes {
    final seconds = double.tryParse(
      estimatedDuration.trim().replaceFirst(RegExp(r's$'), ''),
    );
    if (seconds == null || !seconds.isFinite || seconds < 0) return null;
    return (seconds / 60).ceil();
  }

  factory GoBookingQuote.fromCallable(Object? value) {
    final data = _map(value);
    final distance = _integer(data['distanceMeters']);
    final fare = _decimal(data['estimatedFare']);
    final polyline = _text(data['authoritativeRoutePolyline']);
    final token = _text(data['quoteToken']);
    if (distance == null ||
        distance <= 0 ||
        fare == null ||
        fare < 0 ||
        polyline == null ||
        token == null) {
      throw const GoQuoteException(
        'The route service returned an incomplete quote. Please try again.',
      );
    }
    return GoBookingQuote(
      distanceMeters: distance,
      estimatedFare: fare,
      estimatedDuration: _text(data['estimatedDuration']) ?? '',
      encodedPolyline: polyline,
      fareBreakdown: _map(data['fareBreakdown']),
      fareVersion: _integer(data['fareVersion']) ?? 0,
      isOutsideToda: data['isOutsideToda'] == true,
      coverageClass: _text(data['coverageClass']) ?? 'unconfigured_fallback',
      routePolicy: RoutePolicyAdvisory.fromMap(data['highwayRouteAdvisory'])
          .copyWith(
            avoidedRestrictionNames: _strings(
              data['avoidedRouteRestrictionNames'],
            ),
          ),
      quoteToken: token,
      quoteExpiresAt: DateTime.tryParse(_text(data['quoteExpiresAt']) ?? ''),
    );
  }
}

class GoServiceBridge {
  GoServiceBridge({
    FirebaseFunctions? functions,
    GoQuoteCallable? quoteCallable,
  }) : _functions = quoteCallable == null
           ? functions ??
                 FirebaseFunctions.instanceFor(region: 'asia-southeast1')
           : functions,
       _quoteCallable = quoteCallable;

  static final GoServiceBridge instance = GoServiceBridge();

  final FirebaseFunctions? _functions;
  final GoQuoteCallable? _quoteCallable;

  Future<GoBookingQuote?> tryBookingQuote({
    required LatLng pickup,
    required LatLng destination,
    required int additionalPassengers,
    required int baggageCount,
  }) async {
    final input = <String, dynamic>{
      'pickup': {'latitude': pickup.latitude, 'longitude': pickup.longitude},
      'destination': {
        'latitude': destination.latitude,
        'longitude': destination.longitude,
      },
      'additionalPassengers': additionalPassengers,
      'baggageCount': baggageCount,
    };
    try {
      final Object? response;
      if (_quoteCallable != null) {
        response = await _quoteCallable(input);
      } else {
        response =
            (await _functions!
                    .httpsCallable('createBookingQuote')
                    .call<Map<Object?, Object?>>(input))
                .data;
      }
      return GoBookingQuote.fromCallable(response);
    } on FirebaseFunctionsException catch (error) {
      final bridgeDisabled =
          error.code == 'failed-precondition' &&
          error.message?.contains('Go quote bridge is not enabled') == true;
      if (bridgeDisabled ||
          const {
            'unavailable',
            'deadline-exceeded',
            'internal',
            'not-found',
            'unimplemented',
          }.contains(error.code)) {
        return null;
      }
      throw GoQuoteException(
        error.message ?? 'The route and fare request was rejected.',
      );
    }
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, item) => MapEntry(key.toString(), item));
}

String? _text(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}

int? _integer(Object? value) => value is num && value.isFinite
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '');

double? _decimal(Object? value) => value is num && value.isFinite
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '');

List<String> _strings(Object? value) {
  if (value is! Iterable) return const [];
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);
}
