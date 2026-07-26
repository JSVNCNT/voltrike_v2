import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  Stream<String> watchStatus(String bookingId) {
    return FirebaseFirestore.instance
        .collection('bookingCalls')
        .doc(bookingId)
        .snapshots()
        .map((snapshot) => snapshot.data()?['status'] as String? ?? 'starting');
  }

  Future<void> initiateCall(String bookingId) async {
    await _functions
        .httpsCallable('createBookingCallToken')
        .call<Map<Object?, Object?>>({
          'bookingId': bookingId,
          'accepting': false,
        });
  }

  Future<BookingVoiceCallCredentials> createCredentials(
    String bookingId, {
    bool accepting = false,
  }) async {
    final result = await _functions
        .httpsCallable('createBookingCallToken')
        .call<Map<Object?, Object?>>({
          'bookingId': bookingId,
          'accepting': accepting,
        });
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

  Future<void> declineCall(String bookingId, {bool expired = false}) async {
    await _functions
        .httpsCallable('respondBookingCall')
        .call<void>({
          'bookingId': bookingId,
          'response': expired ? 'expired' : 'declined',
        });
  }
}
