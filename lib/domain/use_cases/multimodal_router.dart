import '../models/multimodal_network.dart';
import '../models/journey_data.dart';

enum RoutePreference { fastest, leastWalking, lowestFare, fewestTransfers }

RoutePreference routePreferenceFromLabel(String value) => switch (value) {
  'Least walking' => RoutePreference.leastWalking,
  'Lowest fare' => RoutePreference.lowestFare,
  'Fewest transfers' => RoutePreference.fewestTransfers,
  _ => RoutePreference.fastest,
};

class RouteLeg {
  const RouteLeg({
    required this.mode,
    required this.route,
    required this.from,
    required this.to,
    required this.minutes,
    required this.points,
    this.fromNodeId,
    this.toNodeId,
    this.fare = 0,
  });
  final String mode;
  final TransitRoute? route;
  final String from;
  final String to;
  final int minutes;
  final List<GeoPoint> points;
  final String? fromNodeId;
  final String? toNodeId;
  final int fare;
  bool get isWalking => mode == 'Walk';

  RouteLeg copyWith({
    String? from,
    String? to,
    int? minutes,
    List<GeoPoint>? points,
    String? fromNodeId,
    String? toNodeId,
    int? fare,
  }) => RouteLeg(
    mode: mode,
    route: route,
    from: from ?? this.from,
    to: to ?? this.to,
    minutes: minutes ?? this.minutes,
    points: points ?? this.points,
    fromNodeId: fromNodeId ?? this.fromNodeId,
    toNodeId: toNodeId ?? this.toNodeId,
    fare: fare ?? this.fare,
  );
}

class RoutedJourney {
  const RoutedJourney({
    required this.legs,
    required this.totalMinutes,
    required this.walkingMinutes,
    required this.transfers,
    required this.estimatedFare,
    this.scheduledWaitMinutes = 0,
  });
  final List<RouteLeg> legs;
  final int totalMinutes;
  final int walkingMinutes;
  final int transfers;
  final int estimatedFare;
  final int scheduledWaitMinutes;
}

class MultimodalRouter {
  const MultimodalRouter();

  RoutedJourney? find({
    required MultimodalNetwork network,
    required String originId,
    required String destinationId,
    required RoutePreference preference,
    Set<String> allowedModes = const {'Metro', 'AMTS', 'BRTS'},
    String? requiredFirstMode,
    String? requiredFinalMode,
    RoutingPlace? originOverride,
    RoutingPlace? destinationOverride,
    Map<String, List<ScheduledTrip>> scheduledDepartures = const {},
    int? departureMinutes,
  }) {
    final origin =
        originOverride ??
        network.places.where((place) => place.id == originId).firstOrNull;
    final destination =
        destinationOverride ??
        network.places.where((place) => place.id == destinationId).firstOrNull;
    if (origin == null || destination == null) return null;
    final startNodes = network
        .nearby(origin.point, radiusMeters: 2200, limit: 1000)
        .where((node) => _nodeMatchesAllowedMode(node, allowedModes))
        .take(10)
        .toList();
    if (startNodes.isEmpty) return null;
    final heap = _MinHeap();
    final records = <String, _RouteRecord>{};
    for (final node in startNodes) {
      final walk = _walkingMinutes(distanceMeters(origin.point, node.point));
      final record = _RouteRecord(
        nodeId: node.id,
        lastRouteId: null,
        actualMinutes: walk,
        walkingMinutes: walk,
        transfers: 0,
        score: _score(
          preference,
          actualMinutes: walk,
          walkingMinutes: walk,
          transfers: 0,
          fare: 0,
        ),
        initialWalkMinutes: walk,
      );
      records[record.key] = record;
      heap.add(record);
    }
    _RouteRecord? best;
    int? bestFinishWalk;
    while (heap.isNotEmpty) {
      final current = heap.removeFirst();
      if (records[current.key] != current) continue;
      if (best case final currentBest?
          when current.score >= currentBest.score) {
        break;
      }
      final node = network.nodes[current.nodeId]!;
      final finishDistance = distanceMeters(node.point, destination.point);
      if (finishDistance <= 1200) {
        final finalOperator = current.lastRouteId == null
            ? null
            : network.routes[current.lastRouteId]?.operatorName;
        if (requiredFinalMode != null && finalOperator != requiredFinalMode) {
          continue;
        }
        final finishWalk = _walkingMinutes(finishDistance);
        final total = current.actualMinutes + finishWalk;
        final score = _score(
          preference,
          actualMinutes: total,
          walkingMinutes: current.walkingMinutes + finishWalk,
          transfers: current.transfers,
          fare: current.fare,
        );
        final existingBest = best;
        if (existingBest == null || score < existingBest.score) {
          best = current.copyWith(
            score: score,
            actualMinutes: total,
            walkingMinutes: current.walkingMinutes + finishWalk,
          );
          bestFinishWalk = finishWalk;
        }
      }
      for (final edge in network.edgesFrom(node.id)) {
        if (!allowedModes.contains(edge.mode)) continue;
        if (current.lastRouteId == null &&
            requiredFirstMode != null &&
            edge.mode != requiredFirstMode) {
          continue;
        }
        final transfer =
            current.lastRouteId != null && current.lastRouteId != edge.routeId;
        final next = _advance(
          current: current,
          nodeId: edge.toId,
          routeId: edge.routeId,
          edge: edge,
          addedMinutes:
              edge.minutes +
              (transfer
                  ? 4
                  : current.lastRouteId == null
                  ? 2
                  : 0),
          addedScheduledWait: _scheduledWaitMinutes(
            scheduledDepartures: scheduledDepartures,
            departureMinutes: departureMinutes,
            current: current,
            edge: edge,
          ),
          addedWalking: 0,
          addedTransfers: transfer ? 1 : 0,
          addedFare: _fareForBoarding(
            current.lastRouteId,
            edge.routeId,
            edge.mode,
          ),
          preference: preference,
        );
        _store(records, heap, next);
      }
      for (final nearby in network.nearby(
        node.point,
        radiusMeters: 220,
        limit: 7,
      )) {
        if (nearby.id == node.id) continue;
        final minutes = _walkingMinutes(
          distanceMeters(node.point, nearby.point),
        );
        final edge = TransitEdge(
          fromId: node.id,
          toId: nearby.id,
          routeId: 'walk',
          mode: 'Walk',
          minutes: minutes,
        );
        final next = _advance(
          current: current,
          nodeId: nearby.id,
          routeId: current.lastRouteId,
          edge: edge,
          addedMinutes: minutes,
          addedScheduledWait: 0,
          addedWalking: minutes,
          addedTransfers: 0,
          addedFare: 0,
          preference: preference,
        );
        _store(records, heap, next);
      }
    }
    if (best == null || bestFinishWalk == null) return null;
    final traversal = <_Traversal>[];
    var cursor = best;
    while (cursor.previousKey != null) {
      traversal.add(
        _Traversal(
          edge: cursor.edge!,
          fromId: records[cursor.previousKey]!.nodeId,
          toId: cursor.nodeId,
        ),
      );
      cursor = records[cursor.previousKey]!;
    }
    final legs = _priceLegs(
      network,
      _toLegs(
        network,
        traversal.reversed.toList(),
        origin,
        destination,
        best.initialWalkMinutes,
        bestFinishWalk,
      ),
    );
    return RoutedJourney(
      legs: legs,
      totalMinutes: best.actualMinutes,
      walkingMinutes: best.walkingMinutes,
      transfers: best.transfers,
      estimatedFare: legs.fold(0, (total, leg) => total + leg.fare),
      scheduledWaitMinutes: best.scheduledWaitMinutes,
    );
  }

  _RouteRecord _advance({
    required _RouteRecord current,
    required String nodeId,
    required String? routeId,
    required TransitEdge edge,
    required int addedMinutes,
    required int addedScheduledWait,
    required int addedWalking,
    required int addedTransfers,
    required int addedFare,
    required RoutePreference preference,
  }) {
    final actual = current.actualMinutes + addedMinutes + addedScheduledWait;
    final walking = current.walkingMinutes + addedWalking;
    final transfers = current.transfers + addedTransfers;
    final fare = current.fare + addedFare;
    return _RouteRecord(
      nodeId: nodeId,
      lastRouteId: routeId,
      actualMinutes: actual,
      walkingMinutes: walking,
      transfers: transfers,
      fare: fare,
      score: _score(
        preference,
        actualMinutes: actual,
        walkingMinutes: walking,
        transfers: transfers,
        fare: fare,
      ),
      previousKey: current.key,
      edge: edge,
      initialWalkMinutes: current.initialWalkMinutes,
      scheduledWaitMinutes: current.scheduledWaitMinutes + addedScheduledWait,
    );
  }

  int _scheduledWaitMinutes({
    required Map<String, List<ScheduledTrip>> scheduledDepartures,
    required int? departureMinutes,
    required _RouteRecord current,
    required TransitEdge edge,
  }) {
    if (departureMinutes == null || edge.mode == 'Walk') return 0;
    final departures = scheduledDepartures[current.nodeId]
        ?.where((trip) => trip.routeId == edge.routeId)
        .map((trip) => _clockMinutes(trip.time))
        .toList();
    if (departures == null || departures.isEmpty) return 0;
    departures.sort();
    final readyAt = (departureMinutes + current.actualMinutes) % (24 * 60);
    final next = departures.firstWhere(
      (minutes) => minutes >= readyAt,
      orElse: () => departures.first + 24 * 60,
    );
    return next - readyAt;
  }

  void _store(
    Map<String, _RouteRecord> records,
    _MinHeap heap,
    _RouteRecord next,
  ) {
    final existing = records[next.key];
    if (existing == null || next.score < existing.score) {
      records[next.key] = next;
      heap.add(next);
    }
  }

  List<RouteLeg> _toLegs(
    MultimodalNetwork network,
    List<_Traversal> path,
    RoutingPlace origin,
    RoutingPlace destination,
    int initialWalk,
    int finalWalk,
  ) {
    final legs = <RouteLeg>[];
    if (path.isNotEmpty && initialWalk > 0) {
      final first = network.nodes[path.first.fromId]!;
      legs.add(
        RouteLeg(
          mode: 'Walk',
          route: null,
          from: origin.name,
          to: first.name,
          minutes: initialWalk,
          points: [origin.point, first.point],
          toNodeId: path.first.fromId,
        ),
      );
    }
    for (final traversal in path) {
      final from = network.nodes[traversal.fromId]!;
      final to = network.nodes[traversal.toId]!;
      final route = traversal.edge.mode == 'Walk'
          ? null
          : network.routes[traversal.edge.routeId];
      final last = legs.lastOrNull;
      if (last != null &&
          last.mode == traversal.edge.mode &&
          last.route?.id == route?.id) {
        legs[legs.length - 1] = last.copyWith(
          to: to.name,
          minutes: last.minutes + traversal.edge.minutes,
          points: [...last.points, to.point],
          toNodeId: traversal.toId,
        );
      } else {
        legs.add(
          RouteLeg(
            mode: traversal.edge.mode,
            route: route,
            from: from.name,
            to: to.name,
            minutes: traversal.edge.minutes,
            points: [from.point, to.point],
            fromNodeId: traversal.fromId,
            toNodeId: traversal.toId,
          ),
        );
      }
    }
    if (path.isNotEmpty && finalWalk > 0) {
      final last = network.nodes[path.last.toId]!;
      legs.add(
        RouteLeg(
          mode: 'Walk',
          route: null,
          from: last.name,
          to: destination.name,
          minutes: finalWalk,
          points: [last.point, destination.point],
          fromNodeId: path.last.toId,
        ),
      );
    }
    return legs;
  }

  List<RouteLeg> _priceLegs(MultimodalNetwork network, List<RouteLeg> legs) =>
      legs
          .map(
            (leg) => leg.isWalking
                ? leg
                : leg.copyWith(
                    fare: _fareForDistance(
                      leg.mode,
                      _legDistanceMeters(leg.points),
                      metroFare: _officialMetroFare(network, leg),
                    ),
                  ),
          )
          .toList();
}

int? _officialMetroFare(MultimodalNetwork network, RouteLeg leg) {
  final fromNodeId = leg.fromNodeId;
  final toNodeId = leg.toNodeId;
  if (leg.mode != 'Metro' || fromNodeId == null || toNodeId == null) {
    return null;
  }
  return network.metroFares['$fromNodeId:$toNodeId'];
}

int _walkingMinutes(double meters) => (meters / 75).ceil().clamp(1, 60);
int _clockMinutes(String value) {
  final parts = value.split(':');
  if (parts.length < 2) return 0;
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

bool _nodeMatchesAllowedMode(TransitNode node, Set<String> allowedModes) =>
    node.operatorName == 'AMTS/BRTS'
    ? allowedModes.contains('AMTS') || allowedModes.contains('BRTS')
    : allowedModes.contains(node.operatorName);
int _fareForBoarding(String? previousRoute, String nextRoute, String mode) =>
    previousRoute == nextRoute
    ? 0
    : switch (mode) {
        'Metro' => 5,
        'BRTS' || 'AMTS' => 5,
        _ => 0,
      };
double _legDistanceMeters(List<GeoPoint> points) {
  if (points.length < 2) return 0;
  var total = 0.0;
  for (var index = 1; index < points.length; index++) {
    total += distanceMeters(points[index - 1], points[index]);
  }
  return total;
}

/// Metro uses the bundled GMRC token OD matrix when an exact station pair is
/// present. AMTS/BRTS have no official machine-readable fare chart in the
/// supplied data, so they use a transparent Rs 2/km fallback with a Rs 5
/// minimum and Rs 30 cap.
int _fareForDistance(String mode, double distanceMeters, {int? metroFare}) {
  final kilometers = distanceMeters / 1000;
  return switch (mode) {
    'Metro' when metroFare != null => metroFare,
    'Metro' when kilometers <= 2 => 5,
    'Metro' when kilometers <= 5 => 10,
    'Metro' when kilometers <= 12 => 15,
    'Metro' => 20,
    'AMTS' || 'BRTS' => _busFallbackFare(kilometers),
    _ => 0,
  };
}

int _busFallbackFare(double kilometers) {
  final rawFare = (kilometers * 2).ceil();
  if (rawFare < 5) return 5;
  if (rawFare > 30) return 30;
  return rawFare;
}

int _score(
  RoutePreference preference, {
  required int actualMinutes,
  required int walkingMinutes,
  required int transfers,
  required int fare,
}) => switch (preference) {
  RoutePreference.fastest => actualMinutes,
  RoutePreference.leastWalking => walkingMinutes * 5 + actualMinutes,
  RoutePreference.lowestFare => fare * 10 + actualMinutes,
  RoutePreference.fewestTransfers => transfers * 30 + actualMinutes,
};

class _Traversal {
  const _Traversal({
    required this.edge,
    required this.fromId,
    required this.toId,
  });
  final TransitEdge edge;
  final String fromId;
  final String toId;
}

class _RouteRecord {
  const _RouteRecord({
    required this.nodeId,
    required this.lastRouteId,
    required this.actualMinutes,
    required this.walkingMinutes,
    required this.transfers,
    required this.score,
    required this.initialWalkMinutes,
    this.scheduledWaitMinutes = 0,
    this.fare = 0,
    this.previousKey,
    this.edge,
  });
  final String nodeId;
  final String? lastRouteId;
  final int actualMinutes;
  final int walkingMinutes;
  final int transfers;
  final int fare;
  final int score;
  final int initialWalkMinutes;
  final int scheduledWaitMinutes;
  final String? previousKey;
  final TransitEdge? edge;
  String get key => '$nodeId|${lastRouteId ?? 'start'}';
  _RouteRecord copyWith({
    int? score,
    int? actualMinutes,
    int? walkingMinutes,
  }) => _RouteRecord(
    nodeId: nodeId,
    lastRouteId: lastRouteId,
    actualMinutes: actualMinutes ?? this.actualMinutes,
    walkingMinutes: walkingMinutes ?? this.walkingMinutes,
    transfers: transfers,
    fare: fare,
    score: score ?? this.score,
    initialWalkMinutes: initialWalkMinutes,
    scheduledWaitMinutes: scheduledWaitMinutes,
    previousKey: previousKey,
    edge: edge,
  );
}

class _MinHeap {
  final List<_RouteRecord> _items = [];
  bool get isNotEmpty => _items.isNotEmpty;
  void add(_RouteRecord value) {
    _items.add(value);
    var index = _items.length - 1;
    while (index > 0) {
      final parent = (index - 1) ~/ 2;
      if (_items[parent].score <= value.score) break;
      _items[index] = _items[parent];
      index = parent;
    }
    _items[index] = value;
  }

  _RouteRecord removeFirst() {
    final result = _items.first;
    final last = _items.removeLast();
    if (_items.isNotEmpty) {
      var index = 0;
      while (index * 2 + 1 < _items.length) {
        var child = index * 2 + 1;
        if (child + 1 < _items.length &&
            _items[child + 1].score < _items[child].score) {
          child++;
        }
        if (_items[child].score >= last.score) break;
        _items[index] = _items[child];
        index = child;
      }
      _items[index] = last;
    }
    return result;
  }
}

extension<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
