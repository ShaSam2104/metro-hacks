import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'auth_repository.dart';

class JourneySyncRepository {
  JourneySyncRepository({
    required this.authRepository,
    http.Client? client,
    FlutterSecureStorage? storage,
  }) : _client = client ?? http.Client(),
       _storage = storage ?? const FlutterSecureStorage();

  static const _pendingKey = 'metrolink.pendingJourneySelection';

  final AuthRepository authRepository;
  final http.Client _client;
  final FlutterSecureStorage _storage;
  String? _inMemoryPending;

  Future<void> saveJourneySelection({
    required String uid,
    required String hubId,
    required String? stopId,
    required String? routeId,
    required int arrivalMinutes,
    required int transferMinutes,
  }) async {
    final pending = <String, Object?>{
      'uid': uid,
      'hub_id': hubId,
      'stop_id': stopId,
      'route_id': routeId,
      'arrival_minutes': arrivalMinutes,
      'transfer_minutes': transferMinutes,
    };
    _inMemoryPending = jsonEncode(pending);
    try {
      await _storage.write(key: _pendingKey, value: _inMemoryPending);
    } catch (_) {
      // The current tab can still synchronize its latest choice.
    }
    await flushPending();
  }

  Future<void> flushPending() async {
    final currentSession = authRepository.session.value;
    String? rawPending = _inMemoryPending;
    try {
      rawPending ??= await _storage.read(key: _pendingKey);
    } catch (_) {
      // Use the current-tab queue if WebCrypto persistence is unavailable.
    }
    if (currentSession == null ||
        rawPending == null ||
        !authRepository.isConfigured) {
      return;
    }
    final pending = jsonDecode(rawPending) as Map<String, dynamic>;
    if (pending['uid'] != currentSession.userId) {
      return;
    }
    try {
      var response = await _putSelection(currentSession, pending);
      if (response.statusCode == 401 &&
          await authRepository.refreshAccessToken()) {
        response = await _putSelection(authRepository.session.value!, pending);
      }
      if (response.statusCode == 200) {
        _inMemoryPending = null;
        try {
          await _storage.delete(key: _pendingKey);
        } catch (_) {
          // Nothing else needs to be done for an in-memory-only session.
        }
      }
    } catch (_) {
      // The persisted latest choice is retried after the next authenticated launch.
    }
  }

  Future<http.Response> _putSelection(
    MetroSession currentSession,
    Map<String, dynamic> pending,
  ) {
    return _client.put(
      Uri.parse('${AuthRepository.apiBaseUrl}/v1/journey-selection'),
      headers: {
        'Authorization': 'Bearer ${currentSession.accessToken}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(Map<String, dynamic>.from(pending)..remove('uid')),
    );
  }
}
