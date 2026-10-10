import 'dart:math';

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

class RoutingPlace {
  const RoutingPlace({
    required this.id,
    required this.name,
    required this.point,
    this.modes = const {},
  });
  final String id;
  final String name;
  final GeoPoint point;

  /// An empty set represents a landmark or freely chosen map point.
  final Set<String> modes;

  String get serviceLabel =>
      modes.isEmpty ? 'Area / landmark' : '${modes.join(' / ')} stop';

  String get selectionLabel => '$name - $serviceLabel';
}

class TransitNode {
  const TransitNode({
    required this.id,
    required this.name,
    required this.point,
    required this.operatorName,
  });
  final String id;
  final String name;
  final GeoPoint point;
  final String operatorName;
}

class TransitRoute {
  const TransitRoute({
    required this.id,
    required this.operatorName,
    required this.shortName,
    required this.longName,
  });
  final String id;
  final String operatorName;
  final String shortName;
  final String longName;
}

class TransitEdge {
  const TransitEdge({
    required this.fromId,
    required this.toId,
    required this.routeId,
    required this.mode,
    required this.minutes,
  });
  final String fromId;
  final String toId;
  final String routeId;
  final String mode;
  final int minutes;
}

class MultimodalNetwork {
  MultimodalNetwork({
    required this.places,
    required this.nodes,
    required this.routes,
    required List<TransitEdge> edges,
  }) : _edgesByNode = _indexEdges(edges),
       _spatialIndex = _indexNodes(nodes.values);

  final List<RoutingPlace> places;
  final Map<String, TransitNode> nodes;
  final Map<String, TransitRoute> routes;
  final Map<String, List<TransitEdge>> _edgesByNode;
  final Map<String, List<TransitNode>> _spatialIndex;

  List<TransitEdge> edgesFrom(String nodeId) =>
      _edgesByNode[nodeId] ?? const [];

  List<TransitNode> nearby(
    GeoPoint point, {
    required double radiusMeters,
    int limit = 8,
  }) {
    const cellLatitude = .002;
    final latitudeCell = (point.latitude / cellLatitude).floor();
    final longitudeCell = (point.longitude / cellLatitude).floor();
    final range = max(1, (radiusMeters / (111000 * cellLatitude)).ceil());
    final candidates = <TransitNode>[];
    for (var lat = latitudeCell - range; lat <= latitudeCell + range; lat++) {
      for (
        var lon = longitudeCell - range;
        lon <= longitudeCell + range;
        lon++
      ) {
        candidates.addAll(_spatialIndex['$lat:$lon'] ?? const []);
      }
    }
    candidates.sort(
      (left, right) => distanceMeters(
        point,
        left.point,
      ).compareTo(distanceMeters(point, right.point)),
    );
    return candidates
        .where((node) => distanceMeters(point, node.point) <= radiusMeters)
        .take(limit)
        .toList();
  }

  static Map<String, List<TransitEdge>> _indexEdges(List<TransitEdge> edges) {
    final result = <String, List<TransitEdge>>{};
    for (final edge in edges) {
      (result[edge.fromId] ??= []).add(edge);
    }
    return result;
  }

  static Map<String, List<TransitNode>> _indexNodes(
    Iterable<TransitNode> nodes,
  ) {
    const cell = .002;
    final result = <String, List<TransitNode>>{};
    for (final node in nodes) {
      final key =
          '${(node.point.latitude / cell).floor()}:${(node.point.longitude / cell).floor()}';
      (result[key] ??= []).add(node);
    }
    return result;
  }
}

double distanceMeters(GeoPoint first, GeoPoint second) {
  const earthRadius = 6371000.0;
  final latitude = _radians(second.latitude - first.latitude);
  final longitude = _radians(second.longitude - first.longitude);
  final a =
      sin(latitude / 2) * sin(latitude / 2) +
      cos(_radians(first.latitude)) *
          cos(_radians(second.latitude)) *
          sin(longitude / 2) *
          sin(longitude / 2);
  return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a));
}

double _radians(double value) => value * pi / 180;
