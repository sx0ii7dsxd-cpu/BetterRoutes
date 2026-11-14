import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

enum EmailChangeStage { idle, verifyOld, updating, complete }

class EmailChangeApiException implements Exception {
  const EmailChangeApiException({
    required this.code,
    required this.message,
    this.details = const {},
    this.statusCode,
  });

  final String code;
  final String message;
  final Map<String, Object?> details;
  final int? statusCode;

  @override
  String toString() => message;
}

class EmailChangeStatus {
  const EmailChangeStatus({
    required this.stage,
    this.newEmail,
    this.email,
    this.cooldownUntil,
    this.otpExpiresAt,
    this.resendAvailableAt,
    this.resendCount = 0,
    this.maxResends = 0,
    this.attemptsRemaining = 0,
  });

  final EmailChangeStage stage;
  final String? newEmail;
  final String? email;
  final DateTime? cooldownUntil;
  final DateTime? otpExpiresAt;
  final DateTime? resendAvailableAt;
  final int resendCount;
  final int maxResends;
  final int attemptsRemaining;

  EmailChangeStatus copyWith({int? attemptsRemaining}) {
    return EmailChangeStatus(
      stage: stage,
      newEmail: newEmail,
      email: email,
      cooldownUntil: cooldownUntil,
      otpExpiresAt: otpExpiresAt,
      resendAvailableAt: resendAvailableAt,
      resendCount: resendCount,
      maxResends: maxResends,
      attemptsRemaining: attemptsRemaining ?? this.attemptsRemaining,
    );
  }

  factory EmailChangeStatus.fromData(Object? data) {
    if (data is! Map) {
      throw const FormatException('Email-change status was not an object.');
    }
    final Map<String, Object?> values = Map<String, Object?>.from(data);
    final String? rawStage = values['stage'] as String?;
    final EmailChangeStage stage = switch (rawStage) {
      'idle' => EmailChangeStage.idle,
      'verifyOld' => EmailChangeStage.verifyOld,
      'updating' => EmailChangeStage.updating,
      'complete' => EmailChangeStage.complete,
      _ => throw const FormatException(
        'Email-change status contained an unknown step.',
      ),
    };

    return EmailChangeStatus(
      stage: stage,
      newEmail: values['newEmail'] as String?,
      email: values['email'] as String?,
      cooldownUntil: _dateTime(values['cooldownUntil']),
      otpExpiresAt: _dateTime(values['otpExpiresAt']),
      resendAvailableAt: _dateTime(values['resendAvailableAt']),
      resendCount: _integer(values['resendCount']),
      maxResends: _integer(values['maxResends']),
      attemptsRemaining: _integer(values['attemptsRemaining']),
    );
  }

  static DateTime? _dateTime(Object? value) {
    if (value is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }

  static int _integer(Object? value) {
    return value is num ? value.toInt() : 0;
  }
}

typedef EmailChangeIdTokenProvider = Future<String?> Function();

class EmailChangeService {
  EmailChangeService({
    this.auth,
    http.Client? client,
    String? apiUrl,
    this.idTokenProvider,
  }) : _client = client ?? http.Client(),
       _apiUrl = apiUrl ?? _defaultApiUrl;

  static const String _defaultApiUrl = String.fromEnvironment(
    'EMAIL_CHANGE_API_URL',
  );
  static const Duration _requestTimeout = Duration(seconds: 35);

  final FirebaseAuth? auth;
  final http.Client _client;
  final String _apiUrl;
  final EmailChangeIdTokenProvider? idTokenProvider;

  Future<EmailChangeStatus> getStatus() => _call('emailChangeStatus');

  Future<EmailChangeStatus> start(String newEmail) =>
      _call('startEmailChange', {'newEmail': newEmail});

  Future<EmailChangeStatus> verifyOldCode(String code) =>
      _call('verifyOldEmailCode', {'code': code});

  Future<EmailChangeStatus> resendCode() => _call('resendEmailChangeCode');

  void dispose() => _client.close();

  Future<String> _getIdToken() async {
    final EmailChangeIdTokenProvider? provider = idTokenProvider;
    if (provider != null) {
      final String? token = await provider();
      if (token == null || token.isEmpty) {
        throw const EmailChangeApiException(
          code: 'unauthenticated',
          message: 'Sign in before changing your email.',
          statusCode: 401,
        );
      }
      return token;
    }

    final User? user = (auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) {
      throw const EmailChangeApiException(
        code: 'unauthenticated',
        message: 'Sign in before changing your email.',
        statusCode: 401,
      );
    }
    final String? token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const EmailChangeApiException(
        code: 'unauthenticated',
        message: 'Your sign-in has expired. Sign in again and retry.',
        statusCode: 401,
      );
    }
    return token;
  }

  Future<EmailChangeStatus> _call(
    String action, [
    Map<String, Object?> data = const {},
  ]) async {
    final Uri? endpoint = Uri.tryParse(_apiUrl.trim());
    if (endpoint == null ||
        !endpoint.hasAuthority ||
        (endpoint.scheme != 'https' &&
            !(endpoint.scheme == 'http' &&
                (endpoint.host == 'localhost' ||
                    endpoint.host == '127.0.0.1')))) {
      throw const EmailChangeApiException(
        code: 'failed-precondition',
        message: 'The email-change API URL is not configured correctly.',
      );
    }

    final String token = await _getIdToken();
    late final http.Response response;
    try {
      response = await _client
          .post(
            endpoint,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'action': action, ...data}),
          )
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw const EmailChangeApiException(
        code: 'unavailable',
        message: 'The email service took too long to respond. Please retry.',
      );
    } on http.ClientException {
      throw const EmailChangeApiException(
        code: 'unavailable',
        message: 'Could not connect to the email service. Please retry.',
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        throw const FormatException(
          'The email service returned an invalid response.',
        );
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final Map<String, Object?> payload = _stringMap(decoded);
      final Map<String, Object?> error = _stringMap(payload['error']);
      final String code =
          error['code'] as String? ?? _codeForStatus(response.statusCode);
      final Object? rawDetails = error['details'];
      throw EmailChangeApiException(
        code: code,
        message:
            error['message'] as String? ??
            'Could not complete the email change.',
        details: _stringMap(rawDetails),
        statusCode: response.statusCode,
      );
    }

    return EmailChangeStatus.fromData(decoded);
  }

  static Map<String, Object?> _stringMap(Object? value) {
    if (value is! Map) return const {};
    return value.map<String, Object?>(
      (Object? key, Object? item) => MapEntry(key.toString(), item),
    );
  }

  static String _codeForStatus(int statusCode) {
    return switch (statusCode) {
      400 => 'invalid-argument',
      401 => 'unauthenticated',
      403 => 'permission-denied',
      404 => 'not-found',
      409 => 'already-exists',
      410 => 'deadline-exceeded',
      412 => 'failed-precondition',
      429 => 'resource-exhausted',
      _ => 'unavailable',
    };
  }
}
