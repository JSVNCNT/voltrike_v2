import 'package:cloud_functions/cloud_functions.dart';

class SafetyIncidentResult {
  const SafetyIncidentResult({
    required this.incidentId,
    required this.idempotent,
    required this.deliveryStatus,
  });

  final String incidentId;
  final bool idempotent;
  final String? deliveryStatus;
}

class MySafetyIncident {
  const MySafetyIncident({
    required this.incidentId,
    required this.status,
    required this.responseStatus,
    required this.deliveryStatus,
  });

  final String incidentId;
  final String status;
  final String responseStatus;
  final String? deliveryStatus;

  bool get isActive => status == 'open' && responseStatus != 'resolved';
}

class SafetyRepository {
  SafetyRepository({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFunctions _functions;

  Future<SafetyIncidentResult> triggerSos(
    String bookingId, {
    bool accidental = false,
  }) async {
    final result = await _functions
        .httpsCallable('createSafetyIncident')
        .call<Map<String, dynamic>>({
          'bookingId': bookingId,
          'category': 'sos',
          'acknowledgement': accidental ? 'accidental' : 'needs_review',
        });
    return SafetyIncidentResult(
      incidentId: result.data['incidentId'] as String,
      idempotent: result.data['idempotent'] == true,
      deliveryStatus: result.data['deliveryStatus'] as String?,
    );
  }

  Future<MySafetyIncident?> getMyIncident(String bookingId) async {
    final result = await _functions
        .httpsCallable('getMySafetyIncident')
        .call<Map<String, dynamic>>({'bookingId': bookingId});
    final raw = result.data['incident'];
    if (raw is! Map) return null;
    final incident = Map<String, dynamic>.from(raw);
    return MySafetyIncident(
      incidentId: incident['incidentId'] as String,
      status: incident['status'] as String? ?? 'open',
      responseStatus: incident['responseStatus'] as String? ?? 'reported',
      deliveryStatus: incident['deliveryStatus'] as String?,
    );
  }

  Future<void> updateMyIncident(String bookingId, String action) async {
    await _functions
        .httpsCallable('updateMySafetyIncident')
        .call<Map<String, dynamic>>({'bookingId': bookingId, 'action': action});
  }

  Future<Map<String, dynamic>> shareTripInformation(String bookingId) async {
    final result = await _functions
        .httpsCallable('getShareTripInformation')
        .call<Map<String, dynamic>>({'bookingId': bookingId});
    return Map<String, dynamic>.from(result.data);
  }
}
