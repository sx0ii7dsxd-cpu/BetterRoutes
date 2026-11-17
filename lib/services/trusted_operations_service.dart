import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/approved_truck_model.dart';

class TrustedOperationsException implements Exception {
  const TrustedOperationsException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class TrustedOperationsService {
  TrustedOperationsService({
    FirebaseAuth? auth,
    http.Client? client,
    String? apiBaseUrl,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _client = client ?? http.Client(),
       _apiBaseUrl = apiBaseUrl ?? _defaultApiBaseUrl;

  static const String _defaultApiBaseUrl = String.fromEnvironment(
    'TRUSTED_API_BASE_URL',
  );
  static const Duration _timeout = Duration(seconds: 35);

  final FirebaseAuth _auth;
  final http.Client _client;
  final String _apiBaseUrl;

  void dispose() => _client.close();

  Future<List<ApprovedTruckModel>> listActiveTrucks() async {
    final data = await _post('/api/reads', {'action': 'list-active-trucks'});
    return _maps(data).map(ApprovedTruckModel.fromMap).toList();
  }

  Future<Map<String, Object?>> listOwnRequests() async {
    final data = await _post('/api/reads', {'action': 'list-own-requests'});
    return _map(data);
  }

  Future<List<Map<String, Object?>>> listInvitations() async {
    final data = await _post('/api/reads', {'action': 'list-invitations'});
    return _maps(data);
  }

  Future<List<Map<String, Object?>>> listPendingTruckRequests() async {
    final data = await _post('/api/reads', {'action': 'list-pending-trucks'});
    return _maps(data);
  }

  Future<List<ApprovedTruckModel>> listApprovedTrucks() async {
    final data = await _post('/api/reads', {'action': 'list-approved-trucks'});
    return _maps(data).map(ApprovedTruckModel.fromMap).toList();
  }

  Future<List<Map<String, Object?>>> listOwnershipRequests() async {
    final data = await _post('/api/reads', {
      'action': 'list-ownership-requests',
    });
    return _maps(data);
  }

  Future<List<Map<String, Object?>>> listAllInvitations() async {
    final data = await _post('/api/reads', {'action': 'list-all-invitations'});
    return _maps(data);
  }

  Future<Map<String, Object?>> adminAction(
    String action, [
    Map<String, Object?> data = const {},
  ]) async {
    return _map(await _post('/api/admin', {'action': action, ...data}));
  }

  Future<Map<String, Object?>> requestTruckOwnership(String truckId) async {
    return _map(
      await _post('/api/associations', {
        'action': 'truck-ownership-request',
        'truckId': truckId,
      }),
    );
  }

  Future<Map<String, Object?>> createDriverInvitation({
    required String truckId,
    required String targetUid,
  }) async {
    return _map(
      await _post('/api/invitations', {
        'type': 'driver',
        'truckId': truckId,
        'targetUid': targetUid,
      }),
    );
  }

  Future<Map<String, Object?>> createParticipantInvitation({
    required String shipmentId,
    required String targetUid,
    required String role,
  }) async {
    return _map(
      await _post('/api/invitations', {
        'type': role,
        'shipmentId': shipmentId,
        'targetUid': targetUid,
      }),
    );
  }

  Future<void> acceptInvitation(String token) async {
    await _post('/api/invitations', {'action': 'accept', 'token': token});
  }

  Future<void> deleteWarehouse(String warehouseId) async {
    await _post('/api/warehouses', {
      'action': 'delete',
      'warehouseId': warehouseId,
    });
  }

  Future<Object?> _post(String path, Map<String, Object?> body) async {
    final base = _apiBaseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    final endpoint = Uri.tryParse('$base$path');
    if (endpoint == null ||
        !endpoint.hasAuthority ||
        (endpoint.scheme != 'https' &&
            !(endpoint.scheme == 'http' &&
                (endpoint.host == 'localhost' ||
                    endpoint.host == '127.0.0.1')))) {
      throw const TrustedOperationsException(
        code: 'failed-precondition',
        message: 'The trusted operations API URL is not configured correctly.',
      );
    }

    final user = _auth.currentUser;
    if (user == null) {
      throw const TrustedOperationsException(
        code: 'unauthenticated',
        message: 'Sign in before using identity management.',
        statusCode: 401,
      );
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const TrustedOperationsException(
        code: 'unauthenticated',
        message: 'Your sign-in has expired. Sign in again.',
        statusCode: 401,
      );
    }

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
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const TrustedOperationsException(
        code: 'unavailable',
        message: 'The trusted service took too long to respond.',
      );
    } on http.ClientException {
      throw const TrustedOperationsException(
        code: 'unavailable',
        message: 'Could not connect to the trusted service.',
      );
    }

    Object? payload;
    try {
      payload = jsonDecode(response.body);
    } on FormatException {
      throw const TrustedOperationsException(
        code: 'internal',
        message: 'The trusted service returned an invalid response.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = _map(payload is Map ? payload['error'] : null);
      throw TrustedOperationsException(
        code: error['code'] as String? ?? 'internal',
        message:
            error['message'] as String? ??
            'The trusted operation could not be completed.',
        statusCode: response.statusCode,
      );
    }
    return payload;
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map) {
      throw const FormatException(
        'Trusted service returned an invalid object.',
      );
    }
    return Map<String, Object?>.from(value);
  }

  static List<Map<String, Object?>> _maps(Object? value) {
    if (value is! List) {
      throw const FormatException('Trusted service returned an invalid list.');
    }
    return value.map(_map).toList();
  }
}
