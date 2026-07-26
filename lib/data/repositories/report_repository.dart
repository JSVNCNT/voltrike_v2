import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

class ReportRepository {
  ReportRepository({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFunctions _functions;
  final Uuid _uuid = const Uuid();

  Future<void> create({
    required String bookingId,
    required String reporterId,
    required String reportedUserId,
    required String category,
    required String details,
  }) async {
    // Reporter identity, reported account, and TODA scope are derived from the
    // authenticated booking on the backend. The legacy ID arguments remain in
    // the signature so existing screens do not break during migration.
    await _functions.httpsCallable('createRideReport').call({
      'reportId': _uuid.v4(),
      'bookingId': bookingId,
      'category': category,
      'details': details,
    });
  }
}
