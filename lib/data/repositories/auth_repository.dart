import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class MetroSession {
  const MetroSession({
    required this.userId,
    required this.username,
    required this.role,
    required this.accessToken,
    required this.refreshToken,
  });

  final String userId;
  final String username;
  final String role;
  final String accessToken;
  final String refreshToken;
}

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthRepository {
  AuthRepository({http.Client? client, FlutterSecureStorage? storage})
    : _client = client ?? http.Client(),
      _storage = storage ?? const FlutterSecureStorage();

  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const _userIdKey = 'metrolink.userId';
  static const _usernameKey = 'metrolink.username';
  static const _roleKey = 'metrolink.role';
  static const _accessTokenKey = 'metrolink.accessToken';
  static const _refreshTokenKey = 'metrolink.refreshToken';

  final http.Client _client;
  final FlutterSecureStorage _storage;
  final ValueNotifier<MetroSession?> session = ValueNotifier(null);

  bool get isConfigured => apiBaseUrl.isNotEmpty;

  Future<void> restoreSession() async {
    Map<String, String> values;
    try {
      values = await _storage.readAll();
    } catch (_) {
      // WebCrypto can reject an old browser key after a local build changes.
      // Startup must remain available even when secure persistence is not.
      return;
    }
    final userId = values[_userIdKey];
    final username = values[_usernameKey];
    final accessToken = values[_accessTokenKey];
    final refreshToken = values[_refreshTokenKey];
    if (userId == null ||
        username == null ||
        accessToken == null ||
        refreshToken == null) {
      return;
    }
    var role = values[_roleKey] ?? 'passenger';
    if (isConfigured) {
      try {
        final profile = await _profile(accessToken);
        role = profile['role'] as String? ?? role;
      } catch (_) {
        // An offline restore keeps the last known role and local journey usable.
      }
    }
    final restoredSession = MetroSession(
      userId: userId,
      username: username,
      role: role,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    await _persist(restoredSession);
    session.value = restoredSession;
  }

  Future<void> signInWithUsernamePassword({
    required String username,
    required String password,
  }) => _authenticate('/v1/auth/login', username, password);

  Future<void> createUsernamePasswordAccount({
    required String username,
    required String password,
  }) => _authenticate('/v1/auth/register', username, password);

  Future<void> _authenticate(
    String path,
    String username,
    String password,
  ) async {
    _requireConfiguration();
    final normalizedUsername = normalizeUsername(username);
    if (password.length < 10) {
      throw const FormatException(
        'Use a password with at least 10 characters.',
      );
    }
    final response = await _client.post(
      Uri.parse('$apiBaseUrl$path'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'username': normalizedUsername, 'password': password}),
    );
    final body = _decodeBody(response);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ApiException(body['detail'] as String? ?? 'Authentication failed.');
    }
    final accessToken = body['access_token'] as String?;
    final refreshToken = body['refresh_token'] as String?;
    if (accessToken == null || refreshToken == null) {
      throw const ApiException('The service returned an invalid session.');
    }
    final profile = await _profile(accessToken);
    final nextSession = MetroSession(
      userId: profile['id'] as String? ?? _jwtSubject(accessToken),
      username: profile['username'] as String? ?? normalizedUsername,
      role: profile['role'] as String? ?? 'passenger',
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    await _persist(nextSession);
    session.value = nextSession;
  }

  Future<void> signOut() async {
    try {
      await _storage.deleteAll();
    } catch (_) {
      // The in-memory session is still cleared below.
    }
    session.value = null;
  }

  Future<bool> refreshAccessToken() async {
    final currentSession = session.value;
    if (currentSession == null || !isConfigured) return false;
    try {
      final response = await _client.post(
        Uri.parse('$apiBaseUrl/v1/auth/refresh'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': currentSession.refreshToken}),
      );
      if (response.statusCode != 200) return false;
      final body = _decodeBody(response);
      final accessToken = body['access_token'] as String?;
      final refreshToken = body['refresh_token'] as String?;
      if (accessToken == null || refreshToken == null) return false;
      final nextSession = MetroSession(
        userId: _jwtSubject(accessToken),
        username: currentSession.username,
        role: currentSession.role,
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
      await _persist(nextSession);
      session.value = nextSession;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _persist(MetroSession value) async {
    try {
      await Future.wait([
        _storage.write(key: _userIdKey, value: value.userId),
        _storage.write(key: _usernameKey, value: value.username),
        _storage.write(key: _roleKey, value: value.role),
        _storage.write(key: _accessTokenKey, value: value.accessToken),
        _storage.write(key: _refreshTokenKey, value: value.refreshToken),
      ]);
    } catch (_) {
      // A web session may be memory-only when browser secure storage is unavailable.
    }
  }

  void _requireConfiguration() {
    if (!isConfigured) {
      throw const ApiException(
        'This build has no API_BASE_URL. Continue offline or use the configured Android build.',
      );
    }
  }

  Future<Map<String, dynamic>> _profile(String accessToken) async {
    final response = await _client.get(
      Uri.parse('$apiBaseUrl/v1/me'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    final body = _decodeBody(response);
    if (response.statusCode != 200) {
      throw ApiException(body['detail'] as String? ?? 'Could not load account profile.');
    }
    return body;
  }
}

Map<String, dynamic> _decodeBody(http.Response response) {
  if (response.body.isEmpty) return const {};
  final decoded = jsonDecode(response.body);
  return decoded is Map<String, dynamic> ? decoded : const {};
}

String _jwtSubject(String token) {
  final segments = token.split('.');
  if (segments.length != 3) {
    throw const ApiException('The service returned an invalid access token.');
  }
  final payload = jsonDecode(
    utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
  );
  final subject = (payload as Map<String, dynamic>)['sub'];
  if (subject is! String || subject.isEmpty) {
    throw const ApiException('The service returned an invalid access token.');
  }
  return subject;
}

String normalizeUsername(String username) {
  final normalized = username.trim().toLowerCase();
  if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,31}$').hasMatch(normalized)) {
    throw const FormatException(
      'Use 3-32 lowercase letters, numbers, dots, underscores, or hyphens.',
    );
  }
  return normalized;
}
