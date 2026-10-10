import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/models/multimodal_network.dart';

class MultimodalNetworkRepository {
  const MultimodalNetworkRepository();

  Future<MultimodalNetwork> load() async {
    final decoded =
        jsonDecode(
              await rootBundle.loadString('assets/data/routing_network.json'),
            )
            as Map<String, dynamic>;
    final nodes = <String, TransitNode>{};
    for (final item in decoded['nodes'] as List) {
      final node = Map<String, dynamic>.from(item as Map);
      nodes[node['id'] as String] = TransitNode(
        id: node['id'] as String,
        name: node['name'] as String,
        point: GeoPoint(
          (node['latitude'] as num).toDouble(),
          (node['longitude'] as num).toDouble(),
        ),
        operatorName: node['operator'] as String,
      );
    }
    final routes = <String, TransitRoute>{};
    for (final entry in (decoded['routes'] as Map).entries) {
      final route = Map<String, dynamic>.from(entry.value as Map);
      routes[entry.key as String] = TransitRoute(
        id: entry.key as String,
        operatorName: route['operator'] as String,
        shortName: route['shortName'] as String,
        longName: route['longName'] as String,
      );
    }
    routes['metro-blue-line'] = const TransitRoute(
      id: 'metro-blue-line',
      operatorName: 'Metro',
      shortName: 'Blue Line',
      longName: 'Thaltej Gam - Vastral Gam',
    );
    final edges = (decoded['edges'] as List).map((item) {
      final edge = Map<String, dynamic>.from(item as Map);
      return TransitEdge(
        fromId: edge['from'] as String,
        toId: edge['to'] as String,
        routeId: edge['routeId'] as String,
        mode: edge['mode'] as String,
        minutes: edge['minutes'] as int,
      );
    }).toList();
    final modesByNode = <String, Set<String>>{};
    for (final edge in edges) {
      if (edge.mode == 'Walk') continue;
      (modesByNode[edge.fromId] ??= {}).add(edge.mode);
      (modesByNode[edge.toId] ??= {}).add(edge.mode);
    }
    final places = (decoded['places'] as List).map((item) {
      final place = Map<String, dynamic>.from(item as Map);
      return RoutingPlace(
        id: place['id'] as String,
        name: place['name'] as String,
        point: GeoPoint(
          (place['latitude'] as num).toDouble(),
          (place['longitude'] as num).toDouble(),
        ),
      );
    }).toList();
    final placeIds = places.map((place) => place.id).toSet();
    for (final node in nodes.values) {
      if (!placeIds.add(node.id)) continue;
      places.add(
        RoutingPlace(
          id: node.id,
          name: node.name,
          point: node.point,
          modes: Set.unmodifiable(modesByNode[node.id] ?? const {}),
        ),
      );
    }
    places.sort((left, right) {
      final leftIsLandmark = left.modes.isEmpty ? 0 : 1;
      final rightIsLandmark = right.modes.isEmpty ? 0 : 1;
      final category = leftIsLandmark.compareTo(rightIsLandmark);
      return category == 0 ? left.name.compareTo(right.name) : category;
    });
    return MultimodalNetwork(
      places: places,
      nodes: nodes,
      routes: routes,
      edges: edges,
    );
  }
}
