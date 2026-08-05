import 'package:uuid/uuid.dart';
import '../../core/errors/domain_error_mapper.dart';
import '../../core/services/voltrike_api.dart';

class ReportRepository {
  ReportRepository({VoltrikeApi? api}) : _api = api ?? VoltrikeApi.instance;

  final VoltrikeApi _api;
  final Uuid _uuid = const Uuid();

  Future<void> create({
    required String bookingId,
    required String category,
    required String details,
  }) async {
    // Reporter identity, the reported account, participant roles, and TODA
    // scope are all derived from the authenticated booking on the backend.
    try {
      await _api.operation('createRideReport', {
        'reportId': _uuid.v4(),
        'bookingId': bookingId,
        'category': category,
        'details': details,
      });
    } catch (error) {
      throw DomainErrorMapper.exception(error);
    }
  }
}
