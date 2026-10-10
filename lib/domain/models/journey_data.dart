class JourneySeed {
  const JourneySeed({
    required this.hubs,
    required this.departuresByStop,
    required this.routes,
    required this.accessLinks,
    required this.transferModel,
    required this.sources,
  });

  final List<JourneyHub> hubs;
  final Map<String, List<ScheduledTrip>> departuresByStop;
  final Map<String, BusRoute> routes;
  final List<AccessLink> accessLinks;
  final TransferModel transferModel;
  final Map<String, String> sources;

  JourneyHub hubById(String id) => hubs.firstWhere((hub) => hub.id == id);

  List<ScheduledTrip> tripsForStop(String stopId) =>
      departuresByStop[stopId] ?? const [];
}

class JourneyHub {
  const JourneyHub({
    required this.id,
    required this.name,
    required this.availability,
    required this.candidateStops,
  });

  final String id;
  final String name;
  final String availability;
  final List<FeederStop> candidateStops;

  bool get supportsScheduledTransfer => candidateStops.isNotEmpty;
}

class FeederStop {
  const FeederStop({
    required this.id,
    required this.name,
    required this.directDistanceMeters,
    required this.estimatedTransferMinutes,
  });

  final String id;
  final String name;
  final int directDistanceMeters;
  final int estimatedTransferMinutes;
}

class ScheduledTrip {
  const ScheduledTrip({
    required this.time,
    required this.routeId,
    required this.tripId,
    required this.headsign,
  });

  final String time;
  final String routeId;
  final String tripId;
  final String headsign;
}

class BusRoute {
  const BusRoute({
    required this.id,
    required this.agency,
    required this.shortName,
    required this.longName,
  });

  final String id;
  final String agency;
  final String shortName;
  final String longName;
}

class AccessLink {
  const AccessLink({
    required this.hubId,
    required this.mode,
    required this.destination,
    required this.distanceMeters,
    required this.description,
  });

  final String hubId;
  final String mode;
  final String destination;
  final int distanceMeters;
  final String description;
}

class TransferModel {
  const TransferModel({
    required this.walkSpeedMetersPerMinute,
    required this.stationAccessBufferMinutes,
    required this.label,
  });

  final int walkSpeedMetersPerMinute;
  final int stationAccessBufferMinutes;
  final String label;
}
