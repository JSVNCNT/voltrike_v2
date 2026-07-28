import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voltrike_v2/features/auth/presentation/widgets/registration_back_scope.dart';

void main() {
  testWidgets('system back follows the configured registration step', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/current',
      routes: [
        GoRoute(
          path: '/previous',
          builder: (context, state) =>
              const Scaffold(body: Text('Previous registration step')),
        ),
        GoRoute(
          path: '/current',
          builder: (context, state) => const RegistrationBackScope(
            fallbackRoute: '/previous',
            child: Scaffold(body: Text('Current registration step')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Current registration step'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Previous registration step'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/previous');
    expect(tester.takeException(), isNull);
  });
}
