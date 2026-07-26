import 'package:cloud_functions/cloud_functions.dart';

import '../../app/app_config.dart';
import '../errors/domain_error_mapper.dart';

class SystemDiagnostics {
  const SystemDiagnostics({
    required this.compatible,
    required this.functionsVersion,
    required this.bookingSchemaVersion,
    required this.region,
    required this.projectId,
  });

  final bool compatible;
  final int functionsVersion;
  final int bookingSchemaVersion;
  final String region;
  final String projectId;
}

class SystemDiagnosticsService {
  SystemDiagnosticsService({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFunctions _functions;

  Future<SystemDiagnostics> check() async {
    try {
      final result = await _functions
          .httpsCallable('getSystemDiagnostics')
          .call<Map<Object?, Object?>>();
      final data = result.data;
      final functionsVersion =
          (data['functionsProtocolVersion'] as num?)?.toInt() ?? 0;
      final minimumClient =
          (data['minimumClientProtocolVersion'] as num?)?.toInt() ?? 999;
      final schema = (data['bookingSchemaVersion'] as num?)?.toInt() ?? 0;
      final compatible = data['compatible'] == true &&
          AppConfig.clientProtocolVersion >= minimumClient &&
          functionsVersion == AppConfig.expectedFunctionsProtocolVersion &&
          schema == AppConfig.bookingSchemaVersion;
      return SystemDiagnostics(
        compatible: compatible,
        functionsVersion: functionsVersion,
        bookingSchemaVersion: schema,
        region: data['region'] as String? ?? 'unknown',
        projectId: data['projectId'] as String? ?? 'unknown',
      );
    } catch (error) {
      throw DomainErrorMapper.exception(error);
    }
  }
}
