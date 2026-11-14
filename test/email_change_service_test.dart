import 'dart:convert';

import 'package:better_routes/pages/email_change_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('parses pending email-change status and cooldown timestamps', () {
    final EmailChangeStatus status = EmailChangeStatus.fromData({
      'stage': 'verifyOld',
      'newEmail': 'new@example.com',
      'cooldownUntil': 1_800_000_000_000,
      'otpExpiresAt': 1_799_999_400_000,
      'resendAvailableAt': 1_799_999_460_000,
      'resendCount': 1,
      'maxResends': 3,
      'attemptsRemaining': 4,
    });

    expect(status.stage, EmailChangeStage.verifyOld);
    expect(status.newEmail, 'new@example.com');
    expect(
      status.cooldownUntil,
      DateTime.fromMillisecondsSinceEpoch(1_800_000_000_000),
    );
    expect(status.resendCount, 1);
    expect(status.attemptsRemaining, 4);
  });

  test('parses the completed single-code email change', () {
    final EmailChangeStatus status = EmailChangeStatus.fromData({
      'stage': 'complete',
      'email': 'new@example.com',
    });

    expect(status.stage, EmailChangeStage.complete);
    expect(status.email, 'new@example.com');
  });

  test('rejects unknown status steps instead of assuming idle', () {
    expect(
      () => EmailChangeStatus.fromData({'stage': 'verifyNew'}),
      throwsFormatException,
    );
  });

  test(
    'sends a fresh Firebase token and preserves the HTTP status contract',
    () async {
      var tokenRequests = 0;
      final service = EmailChangeService(
        apiUrl: 'https://example.test/api/email-change',
        idTokenProvider: () async {
          tokenRequests += 1;
          return 'firebase-id-token-$tokenRequests';
        },
        client: MockClient((http.Request request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/email-change');
          expect(
            request.headers['authorization'],
            'Bearer firebase-id-token-$tokenRequests',
          );
          expect(jsonDecode(request.body), {'action': 'emailChangeStatus'});
          return http.Response(
            jsonEncode({'stage': 'idle', 'email': null}),
            200,
          );
        }),
      );
      addTearDown(service.dispose);

      final EmailChangeStatus status = await service.getStatus();

      expect(status.stage, EmailChangeStage.idle);
      expect(tokenRequests, 1);
    },
  );

  test('preserves API error details for failed OTP attempts', () async {
    final service = EmailChangeService(
      apiUrl: 'https://example.test/api/email-change',
      idTokenProvider: () async => 'firebase-id-token',
      client: MockClient((_) async {
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'permission-denied',
              'message': 'That code is incorrect.',
              'details': {'attemptsRemaining': 4},
            },
          }),
          403,
        );
      }),
    );
    addTearDown(service.dispose);

    await expectLater(
      service.verifyOldCode('123456'),
      throwsA(
        isA<EmailChangeApiException>()
            .having((error) => error.code, 'code', 'permission-denied')
            .having(
              (error) => error.details['attemptsRemaining'],
              'attemptsRemaining',
              4,
            ),
      ),
    );
  });

  test('does not make a request without a Firebase ID token', () async {
    final service = EmailChangeService(
      apiUrl: 'https://example.test/api/email-change',
      idTokenProvider: () async => null,
      client: MockClient((_) async {
        fail('The request must not be sent without a Firebase ID token.');
      }),
    );
    addTearDown(service.dispose);

    await expectLater(
      service.getStatus(),
      throwsA(
        isA<EmailChangeApiException>().having(
          (error) => error.code,
          'code',
          'unauthenticated',
        ),
      ),
    );
  });
}
