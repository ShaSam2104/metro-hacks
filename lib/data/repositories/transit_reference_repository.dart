import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_repository.dart';

class TransitReferenceItem {
  const TransitReferenceItem({
    required this.id,
    required this.entityType,
    required this.operatorName,
    required this.payload,
    required this.updatedAt,
  });

  final String id;
  final String entityType;
  final String operatorName;
  final Map<String, dynamic> payload;
  final DateTime updatedAt;

  factory TransitReferenceItem.fromJson(Map<String, dynamic> json) {
    return TransitReferenceItem(
      id: json['id'] as String,
      entityType: json['entity_type'] as String,
      operatorName: json['operator'] as String,
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  String get title => entityType == 'station'
      ? payload['name'] as String? ?? id
      : '${payload['short_name'] ?? id} · ${payload['long_name'] ?? ''}';

  String get status => payload['status'] as String? ?? 'active';
}

class TransitReferenceRepository {
  TransitReferenceRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<TransitReferenceItem>> list(MetroSession session) async {
    final response = await _client.get(
      Uri.parse('${AuthRepository.apiBaseUrl}/v1/transit/reference'),
      headers: _headers(session),
    );
    final decoded = _decode(response);
    if (response.statusCode != 200 || decoded is! List) {
      throw ApiException(_message(decoded, 'Could not load network reference.'));
    }
    return decoded
        .whereType<Map>()
        .map((item) => TransitReferenceItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> saveStation({
    required MetroSession session,
    required String id,
    required String name,
    required String status,
    String? latitude,
    String? longitude,
  }) => _put(
    session,
    '/v1/transit/stations/${Uri.encodeComponent(id)}',
    {
      'name': name.trim(),
      'status': status,
      if (latitude != null && latitude.trim().isNotEmpty) 'latitude': double.parse(latitude),
      if (longitude != null && longitude.trim().isNotEmpty) 'longitude': double.parse(longitude),
    },
  );

  Future<void> saveRoute({
    required MetroSession session,
    required String operatorName,
    required String id,
    required String shortName,
    required String longName,
    required String status,
    String? note,
    List<Map<String, double>>? geometry,
  }) => _put(
    session,
    '/v1/transit/routes/$operatorName/${Uri.encodeComponent(id)}',
    {
      'short_name': shortName.trim(),
      'long_name': longName.trim(),
      'status': status,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (geometry != null && geometry.isNotEmpty) 'geometry': geometry,
    },
  );

  Future<void> delete({required MetroSession session, required String id}) async {
    final response = await _client.delete(
      Uri.parse('${AuthRepository.apiBaseUrl}/v1/transit/reference/${Uri.encodeComponent(id)}'),
      headers: _headers(session),
    );
    if (response.statusCode != 204) {
      throw ApiException(_message(_decode(response), 'Could not remove network reference.'));
    }
  }

  Future<void> _put(MetroSession session, String path, Map<String, dynamic> body) async {
    final response = await _client.put(
      Uri.parse('${AuthRepository.apiBaseUrl}$path'),
      headers: _headers(session),
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw ApiException(_message(_decode(response), 'Could not save network reference.'));
    }
  }

  Map<String, String> _headers(MetroSession session) => {
    'Authorization': 'Bearer ${session.accessToken}',
    'Content-Type': 'application/json',
  };
}

dynamic _decode(http.Response response) {
  if (response.body.isEmpty) return null;
  try {
    return jsonDecode(response.body);
  } catch (_) {
    return null;
  }
}

String _message(dynamic body, String fallback) =>
    body is Map && body['detail'] is String ? body['detail'] as String : fallback;
