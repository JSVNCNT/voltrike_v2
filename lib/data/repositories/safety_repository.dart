import '../../core/services/voltrike_api.dart';

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
  SafetyRepository({VoltrikeApi? api}) : _api = api ?? VoltrikeApi.instance;

  final VoltrikeApi _api;

  Future<SafetyIncidentResult> triggerSos(
    String bookingId, {
    bool accidental = false,
  }) async {
    final data = await _api.operation('createSafetyIncident', {
      'bookingId': bookingId,
      'category': 'sos',
      'acknowledgement': accidental ? 'accidental' : 'needs_review',
    });
    return SafetyIncidentResult(
      incidentId: data['incidentId'] as String,
      idempotent: data['idempotent'] == true,
      deliveryStatus: data['deliveryStatus'] as String?,
    );
  }

  Future<MySafetyIncident?> getMyIncident(String bookingId) async {
    final result = await _api.operation('getMySafetyIncident', {
      'bookingId': bookingId,
    });
    final raw = result['incident'];
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
    await _api.operation('updateMySafetyIncident', {
      'bookingId': bookingId,
      'action': action,
    });
  }

  Future<Map<String, dynamic>> shareTripInformation(String bookingId) async {
    return _api.operation('getShareTripInformation', {'bookingId': bookingId});
  }
}
