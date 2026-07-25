import 'package:cloud_functions/cloud_functions.dart';

class BookingVoiceCallCredentials {
  const BookingVoiceCallCredentials({
    required this.serverUrl,
    required this.token,
  });

  final String serverUrl;
  final String token;
}

/// Retrieves a short-lived, booking-authorized LiveKit token from Firebase.
/// The LiveKit API secret remains exclusively in Cloud Functions.
class BookingVoiceCallRepository {
  BookingVoiceCallRepository({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFunctions _functions;

  Future<BookingVoiceCallCredentials> createCredentials(String bookingId) async {
    final result = await _functions
        .httpsCallable('createBookingCallToken')
        .call<Map<Object?, Object?>>({'bookingId': bookingId});
    final data = result.data;
    final serverUrl = data['serverUrl'] as String?;
    final token = data['token'] as String?;
    if (serverUrl == null || token == null) {
      throw StateError('Voice service returned incomplete call credentials.');
    }
    return BookingVoiceCallCredentials(serverUrl: serverUrl, token: token);
  }

  Future<void> endCall(String bookingId) async {
    await _functions
        .httpsCallable('endBookingCall')
        .call<void>({'bookingId': bookingId});
  }
}
