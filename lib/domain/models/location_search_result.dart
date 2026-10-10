import 'multimodal_network.dart';

class LocationSearchResult {
  const LocationSearchResult({
    required this.name,
    required this.point,
    required this.source,
  });

  final String name;
  final GeoPoint point;
  final String source;
}
