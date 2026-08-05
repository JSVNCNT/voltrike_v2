import '../../app/app_config.dart';
import '../errors/domain_error_mapper.dart';
import 'voltrike_api.dart';

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
  SystemDiagnosticsService({VoltrikeApi? api})
    : _api = api ?? VoltrikeApi.instance;

  final VoltrikeApi _api;

  Future<SystemDiagnostics> check() async {
    try {
      final data = await _api.operation('getSystemDiagnostics', const {});
      final functionsVersion =
          (data['functionsProtocolVersion'] as num?)?.toInt() ?? 0;
      final minimumClient =
          (data['minimumClientProtocolVersion'] as num?)?.toInt() ?? 999;
      final schema = (data['bookingSchemaVersion'] as num?)?.toInt() ?? 0;
      final compatible =
          data['compatible'] == true &&
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
