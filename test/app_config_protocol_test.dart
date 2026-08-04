import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/app/app_config.dart';

void main() {
  test('mobile diagnostics expect the deployed Functions protocol', () {
    expect(AppConfig.expectedFunctionsProtocolVersion, 4);
    expect(AppConfig.clientProtocolVersion, 3);
  });
}
