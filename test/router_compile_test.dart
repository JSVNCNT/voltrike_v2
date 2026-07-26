import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/app/router.dart';

void main() {
  test('application router builds with booking coordinators', () {
    expect(appRouter.routeInformationProvider.value.uri.path, '/');
  });
}
