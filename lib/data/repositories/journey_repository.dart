import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/models/journey_data.dart';

class JourneyRepository {
  const JourneyRepository();

  Future<JourneySeed> load() async {
    final raw = await rootBundle.loadString('assets/data/journey_seed.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return _parseSeed(json);
  }

  JourneySeed _parseSeed(Map<String, dynamic> json) {
    final hubs = (json['hubs'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(
          (hub) => JourneyHub(
            id: hub['id'] as String,
            name: hub['name'] as String,
            availability: hub['availability'] as String,
            candidateStops: (hub['candidateStops'] as List<dynamic>)
                .cast<Map<String, dynamic>>()
                .map(
                  (stop) => FeederStop(
                    id: stop['id'] as String,
                    name: stop['name'] as String,
                    directDistanceMeters: stop['directDistanceM'] as int,
                    estimatedTransferMinutes:
                        stop['estimatedTransferMin'] as int,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
    final departures = <String, List<ScheduledTrip>>{};
    for (final entry
        in (json['busDepartures'] as Map<String, dynamic>).entries) {
      departures[entry.key] = (entry.value as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (trip) => ScheduledTrip(
              time: trip['time'] as String,
              routeId: trip['routeId'] as String,
              tripId: trip['tripId'] as String,
              headsign: trip['headsign'] as String,
            ),
          )
          .toList();
    }
    final routes = <String, BusRoute>{};
    for (final entry in (json['busRoutes'] as Map<String, dynamic>).entries) {
      final route = entry.value as Map<String, dynamic>;
      routes[entry.key] = BusRoute(
        id: entry.key,
        agency: route['agency'] as String,
        shortName: route['shortName'] as String,
        longName: route['longName'] as String,
      );
    }
    final accessLinks = (json['stationAccessLinks'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(
          (link) => AccessLink(
            hubId: link['hubId'] as String,
            mode: link['mode'] as String,
            destination: link['destination'] as String,
            distanceMeters: link['distanceM'] as int,
            description: link['description'] as String,
          ),
        )
        .toList();
    final model = json['transferModel'] as Map<String, dynamic>;
    return JourneySeed(
      hubs: hubs,
      departuresByStop: departures,
      routes: routes,
      accessLinks: accessLinks,
      transferModel: TransferModel(
        walkSpeedMetersPerMinute: model['walkSpeedMetersPerMinute'] as int,
        stationAccessBufferMinutes: model['stationAccessBufferMin'] as int,
        label: model['label'] as String,
      ),
      sources: (json['sources'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, value as String),
      ),
    );
  }
}
