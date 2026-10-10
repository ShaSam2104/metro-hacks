import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/location_search_result.dart';
import '../../domain/models/multimodal_network.dart';
import 'auth_repository.dart';

/// Looks up place names through the backend's Ahmedabad-bounded OSM proxy.
/// The view model always adds its bundled stop-index matches as an offline
/// fallback, so this repository is deliberately allowed to fail quietly.
class LocationSearchRepository {
  LocationSearchRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<LocationSearchResult>> search(String query) async {
    if (AuthRepository.apiBaseUrl.isEmpty || query.trim().length < 2) {
      return const [];
    }
    final uri = Uri.parse(
      '${AuthRepository.apiBaseUrl}/v1/places/search',
    ).replace(queryParameters: {'q': query.trim()});
    final response = await _client.get(uri).timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) return const [];
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return decoded.whereType<Map>().map((item) {
      final value = Map<String, dynamic>.from(item);
      return LocationSearchResult(
        name: value['name'] as String,
        point: GeoPoint(
          (value['latitude'] as num).toDouble(),
          (value['longitude'] as num).toDouble(),
        ),
        source: 'OpenStreetMap',
      );
    }).toList();
  }
}
