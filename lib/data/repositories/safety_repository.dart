import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

class SafetyRepository {
  SafetyRepository({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFunctions _functions;
  static const Uuid _uuid = Uuid();

  Future<void> triggerSos(String bookingId) async {
    await _functions.httpsCallable('createSafetyIncident').call<void>({
      'incidentId': _uuid.v4(),
      'bookingId': bookingId,
      'category': 'sos',
    });
  }

  Future<Map<String, dynamic>> shareTripInformation(String bookingId) async {
    final result = await _functions
        .httpsCallable('getShareTripInformation')
        .call<Map<String, dynamic>>({'bookingId': bookingId});
    return Map<String, dynamic>.from(result.data);
  }
}
