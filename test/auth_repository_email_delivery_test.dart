import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:voltrike_v2/core/services/voltrike_api.dart';
import 'package:voltrike_v2/data/repositories/auth_repository.dart';
import 'package:voltrike_v2/data/services/auth_service.dart';

void main() {
  test(
    'password recovery uses the public API without Firebase sign-in',
    () async {
      final auth = _EmailAuthService();
      final api = VoltrikeApi(
        baseUrl: 'https://api.example.test',
        authTokenProvider: () async =>
            throw StateError('Must remain anonymous'),
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/auth/password-reset');
          expect(request.headers.containsKey('Authorization'), isFalse);
          expect(jsonDecode(request.body), {'email': 'rider@example.test'});
          return _success({'accepted': true});
        }),
      );

      await AuthRepository(
        authService: auth,
        api: api,
      ).sendPasswordResetEmail(' rider@example.test ');

      expect(auth.passwordResetEmails, isEmpty);
    },
  );

  test(
    'verification syncs its profile and requests a branded Go email',
    () async {
      final names = <String>[];
      final repository = _repository(_EmailAuthService(), (request) async {
        expect(request.headers['Authorization'], 'Bearer firebase-id-token');
        final command = jsonDecode(request.body) as Map<String, dynamic>;
        expect(command['commandId'], isNotEmpty);
        expect(command['payload'], isEmpty);
        names.add(request.url.path.split('/').last);
        return _success({'sent': true});
      });

      expect(
        await repository.sendEmailVerification(),
        VerificationEmailDelivery.branded,
      );
      expect(names, [
        'syncMyEmailVerification',
        'requestBrandedVerificationEmail',
      ]);
    },
  );

  test('an already verified account does not send another email', () async {
    final auth = _EmailAuthService()..verified = true;
    final repository = _repository(auth, (request) async {
      expect(request.url.path.split('/').last, 'syncMyEmailVerification');
      return _success({'emailVerified': true});
    });

    expect(
      await repository.sendEmailVerification(),
      VerificationEmailDelivery.alreadyVerified,
    );
    expect(auth.verificationEmails, 0);
  });

  test('Go can report verification completed during the request', () async {
    final repository = _repository(_EmailAuthService(), (_) async {
      return _success({'alreadyVerified': true});
    });

    expect(
      await repository.sendEmailVerification(),
      VerificationEmailDelivery.alreadyVerified,
    );
  });

  for (final code in [
    'not_found',
    'unimplemented',
    'internal',
    'unavailable',
  ]) {
    test('verification falls back to Firebase for $code', () async {
      final auth = _EmailAuthService();
      final repository = _repository(auth, (request) async {
        if (request.url.path.endsWith('/syncMyEmailVerification')) {
          return _success({});
        }
        return _failure(code);
      });

      expect(
        await repository.sendEmailVerification(),
        VerificationEmailDelivery.firebaseFallback,
      );
      expect(auth.verificationEmails, 1);
    });
  }

  test('verification rate limits never send a second Firebase email', () async {
    final auth = _EmailAuthService();
    final repository = _repository(auth, (request) async {
      if (request.url.path.endsWith('/syncMyEmailVerification')) {
        return _success({});
      }
      return _failure('resource_exhausted', status: 429);
    });

    await expectLater(
      repository.sendEmailVerification(),
      throwsA(
        isA<VoltrikeApiException>().having(
          (error) => error.code,
          'code',
          'resource_exhausted',
        ),
      ),
    );
    expect(auth.verificationEmails, 0);
  });

  test(
    'password recovery retains Firebase fallback on provider failure',
    () async {
      final auth = _EmailAuthService();
      final repository = _repository(
        auth,
        (_) async => _failure('unavailable'),
      );

      await repository.sendPasswordResetEmail('rider@example.test');

      expect(auth.passwordResetEmails, ['rider@example.test']);
    },
  );

  test(
    'password recovery rate limits never bypass the provider cooldown',
    () async {
      final auth = _EmailAuthService();
      final repository = _repository(
        auth,
        (_) async => _failure('resource_exhausted', status: 429),
      );

      await expectLater(
        repository.sendPasswordResetEmail('rider@example.test'),
        throwsA(isA<VoltrikeApiException>()),
      );
      expect(auth.passwordResetEmails, isEmpty);
    },
  );

  test('an unavailable network preserves Firebase password recovery', () async {
    final auth = _EmailAuthService();
    final repository = _repository(auth, (_) async {
      throw http.ClientException('Connection refused');
    });

    await repository.sendPasswordResetEmail('rider@example.test');

    expect(auth.passwordResetEmails, ['rider@example.test']);
  });

  test('profile sync failure does not prevent branded verification', () async {
    final repository = _repository(_EmailAuthService(), (request) async {
      if (request.url.path.endsWith('/syncMyEmailVerification')) {
        return _failure('unavailable');
      }
      return _success({'sent': true});
    });

    expect(
      await repository.sendEmailVerification(),
      VerificationEmailDelivery.branded,
    );
  });
}

AuthRepository _repository(
  _EmailAuthService auth,
  Future<http.Response> Function(http.Request) handler,
) {
  return AuthRepository(
    authService: auth,
    api: VoltrikeApi(
      baseUrl: 'https://api.example.test',
      authTokenProvider: () async => 'firebase-id-token',
      client: MockClient(handler),
    ),
  );
}

http.Response _success(Map<String, dynamic> data) {
  return http.Response(jsonEncode({'data': data}), 200);
}

http.Response _failure(String code, {int status = 503}) {
  return http.Response(
    jsonEncode({
      'error': {
        'code': code,
        'message': 'Email service could not complete the request.',
      },
    }),
    status,
  );
}

class _EmailAuthService implements AuthService {
  bool verified = false;
  int verificationEmails = 0;
  final passwordResetEmails = <String>[];

  @override
  bool get isEmailVerified => verified;

  @override
  Future<void> reloadUser() async {}

  @override
  Future<void> sendEmailVerification() async {
    verificationEmails++;
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    passwordResetEmails.add(email);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
