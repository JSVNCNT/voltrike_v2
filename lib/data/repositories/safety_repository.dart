import 'package:cloud_functions/cloud_functions.dart';

class SafetyRepository {
  SafetyRepository({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFunctions _functions;

  Future<bool> triggerSos(String bookingId) async {
    final result = await _functions
        .httpsCallable('createSafetyIncident')
        .call<Map<String, dynamic>>({
          'bookingId': bookingId,
          'category': 'sos',
        });
    return result.data['idempotent'] == true;
  }

  Future<Map<String, dynamic>> shareTripInformation(String bookingId) async {
    final result = await _functions
        .httpsCallable('getShareTripInformation')
        .call<Map<String, dynamic>>({'bookingId': bookingId});
    return Map<String, dynamic>.from(result.data);
  }
}
