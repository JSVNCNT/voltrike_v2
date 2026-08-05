import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

typedef VoltrikeTokenProvider = Future<String?> Function();

class VoltrikeApiException implements Exception {
  const VoltrikeApiException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => message;
}

class VoltrikeApi {
  VoltrikeApi({
    http.Client? client,
    FirebaseAuth? auth,
    String? baseUrl,
    VoltrikeTokenProvider? appCheckTokenProvider,
  }) : _client = client ?? http.Client(),
       _auth = auth ?? FirebaseAuth.instance,
       _baseUrl = (baseUrl ?? _configuredBaseUrl()).replaceFirst(
         RegExp(r'/$'),
         '',
       ),
       _appCheckTokenProvider =
           appCheckTokenProvider ?? FirebaseAppCheck.instance.getToken;

  static final VoltrikeApi instance = VoltrikeApi();

  final http.Client _client;
  final FirebaseAuth _auth;
  final String _baseUrl;
  final VoltrikeTokenProvider? _appCheckTokenProvider;

  static String _configuredBaseUrl() {
    const configured = String.fromEnvironment('VOLTRIKE_API_BASE_URL');
    if (configured.trim().isNotEmpty) return configured.trim();
    return kIsWeb ? 'http://127.0.0.1:8080' : 'http://10.0.2.2:8080';
  }

  Future<Map<String, dynamic>> quote({
    required Map<String, dynamic> pickup,
    required Map<String, dynamic> destination,
    required int additionalPassengers,
    required int baggageCount,
  }) async {
    final response = await _request(
      'POST',
      '/api/v2/quotes',
      body: <String, dynamic>{
        'pickup': pickup,
        'destination': destination,
        'additionalPassengers': additionalPassengers,
        'baggageCount': baggageCount,
      },
    );
    final data = _record(response['data']);
    final quote = _record(data['quote']);
    return <String, dynamic>{...quote, 'quoteToken': data['quoteToken']};
  }

  Future<Map<String, dynamic>> createBooking(Map<String, dynamic> command) {
    return _request(
      'POST',
      '/api/v2/bookings',
      body: command,
    ).then((response) => _record(response['data']));
  }

  Future<Map<String, dynamic>> booking(String bookingId) {
    return _request(
      'GET',
      '/api/v2/bookings/$bookingId',
    ).then((response) => _record(response['data']));
  }

  Future<Map<String, dynamic>> transitionBooking(
    String bookingId,
    Map<String, dynamic> command,
  ) {
    return _request(
      'POST',
      '/api/v2/bookings/$bookingId/commands',
      body: command,
    ).then((response) => _record(response['data']));
  }

  Future<Map<String, dynamic>> createDriverSession(
    Map<String, dynamic> command,
  ) {
    return _request(
      'POST',
      '/api/v2/driver/sessions',
      body: command,
    ).then((response) => _record(response['data']));
  }

  Future<Map<String, dynamic>> heartbeat(
    String sessionId,
    Map<String, dynamic> command,
  ) {
    return _request(
      'POST',
      '/api/v2/driver/sessions/$sessionId/heartbeat',
      body: command,
    ).then((response) => _record(response['data']));
  }

  Future<void> updateLocation(
    String sessionId,
    Map<String, dynamic> command,
  ) async {
    await _request(
      'PUT',
      '/api/v2/driver/sessions/$sessionId/location',
      body: command,
    );
  }

  Future<Map<String, dynamic>> operation(
    String name,
    Map<String, dynamic> payload, {
    String? commandId,
  }) {
    return _request(
      'POST',
      '/api/v2/operations/${Uri.encodeComponent(name)}',
      body: <String, dynamic>{'commandId': ?commandId, 'payload': payload},
    ).then((response) => _record(response['data']));
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final user = _auth.currentUser;
    final token = await user?.getIdToken();
    if (token == null || token.isEmpty) {
      throw const VoltrikeApiException(
        'Sign in is required before using the VolTrike API.',
        code: 'unauthenticated',
      );
    }
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final appCheckToken = await _appCheckTokenProvider?.call();
    if (appCheckToken != null && appCheckToken.trim().isNotEmpty) {
      headers['X-Firebase-AppCheck'] = appCheckToken.trim();
    }
    final uri = Uri.parse('$_baseUrl$path');
    late http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await _client.get(uri, headers: headers);
          break;
        case 'POST':
          response = await _client.post(
            uri,
            headers: headers,
            body: jsonEncode(body ?? const <String, dynamic>{}),
          );
          break;
        case 'PUT':
          response = await _client.put(
            uri,
            headers: headers,
            body: jsonEncode(body ?? const <String, dynamic>{}),
          );
          break;
        default:
          throw const VoltrikeApiException('Unsupported API method.');
      }
    } catch (error) {
      if (error is VoltrikeApiException) rethrow;
      throw VoltrikeApiException('The VolTrike API is unavailable: $error');
    }
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = _record(decoded['error']);
      throw VoltrikeApiException(
        (error['message'] as String?) ?? 'The API request was rejected.',
        code: error['code'] as String?,
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  static Map<String, dynamic> _decode(String value) {
    if (value.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(value);
    return _record(decoded);
  }

  static Map<String, dynamic> _record(Object? value) {
    if (value is! Map) return <String, dynamic>{};
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
}
