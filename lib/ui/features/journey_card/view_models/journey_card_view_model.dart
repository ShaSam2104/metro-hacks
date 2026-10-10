import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/journey_repository.dart';
import '../../../../data/repositories/journey_sync_repository.dart';
import '../../../../data/repositories/multimodal_network_repository.dart';
import '../../../../data/repositories/location_search_repository.dart';
import '../../../../domain/models/journey_data.dart';
import '../../../../domain/models/location_search_result.dart';
import '../../../../domain/models/multimodal_network.dart';
import '../../../../domain/use_cases/connection_advisor.dart';
import '../../../../domain/use_cases/multimodal_router.dart';

class JourneyCardViewModel extends ChangeNotifier {
  JourneyCardViewModel({
    JourneyRepository? repository,
    MultimodalNetworkRepository? networkRepository,
    MultimodalRouter? router,
    LocationSearchRepository? locationSearchRepository,
    this.syncRepository,
    this.userId,
  }) : _repository = repository ?? const JourneyRepository(),
       _networkRepository =
           networkRepository ?? const MultimodalNetworkRepository(),
       _router = router ?? const MultimodalRouter(),
       _locationSearchRepository =
           locationSearchRepository ?? LocationSearchRepository();

  final JourneyRepository _repository;
  final MultimodalNetworkRepository _networkRepository;
  final MultimodalRouter _router;
  final LocationSearchRepository _locationSearchRepository;
  final JourneySyncRepository? syncRepository;
  final String? userId;

  JourneySeed? _seed;
  MultimodalNetwork? _network;
  RoutedJourney? _routedJourney;
  String? _selectedHubId;
  String? _selectedStopId;
  String? _selectedRouteId;
  var _arrivalMinutes = 17 * 60 + 48;
  var _transferMinutes = 7;
  var _originId = 'thaltej-gam';
  var _destinationId = 'gujarat-university';
  var _preference = 'Fastest';
  String? _boardingMode;
  String? _finalMode;
  final Set<String> _allowedModes = {'Metro', 'AMTS', 'BRTS'};
  RoutingPlace? _originOverride;
  RoutingPlace? _destinationOverride;
  var _isLoading = true;
  var _routeRevision = 0;
  String? _error;

  bool get isLoading => _isLoading;
  String? get error => _error;
  JourneySeed? get seed => _seed;
  MultimodalNetwork? get network => _network;
  RoutedJourney? get routedJourney => _routedJourney;
  int get routeRevision => _routeRevision;
  JourneyHub? get selectedHub => _selectedHubId == null || _seed == null
      ? null
      : _seed!.hubById(_selectedHubId!);
  FeederStop? get selectedStop {
    final hub = selectedHub;
    if (hub == null || _selectedStopId == null) return null;
    return hub.candidateStops.firstWhere((stop) => stop.id == _selectedStopId);
  }

  int get arrivalMinutes => _arrivalMinutes;
  int get transferMinutes => _transferMinutes;
  String get arrivalTime => formatClockMinutes(_arrivalMinutes);
  String get departureTime => arrivalTime;

  // Exact Metro fares use the bundled GMRC Blue Line OD matrix; bus fares are fallback estimates.
  List<RouteLeg> get fareLegs =>
      _routedJourney?.legs.where((leg) => leg.fare > 0).toList() ?? const [];
  int get metroFareEstimate => fareLegs
      .where((leg) => leg.mode == 'Metro')
      .fold(0, (total, leg) => total + leg.fare);
  int get totalFareEstimate => _routedJourney?.estimatedFare ?? 0;
  String get originId => _originId;
  String get destinationId => _destinationId;
  String get preference => _preference;
  String? get boardingMode => _boardingMode;
  String? get finalMode => _finalMode;
  Set<String> get allowedModes => Set.unmodifiable(_allowedModes);
  bool usesMode(String mode) => _allowedModes.contains(mode);
  List<String> get boardingModes => [
    'Any enabled service',
    ...['Metro', 'AMTS', 'BRTS'].where(_allowedModes.contains),
  ];
  List<String> get finalModes => boardingModes;
  String get originName => _originOverride?.name ?? _placeName(_originId);
  String get destinationName =>
      _destinationOverride?.name ?? _placeName(_destinationId);
  GeoPoint? get originPoint => _originOverride?.point;
  GeoPoint? get destinationPoint => _destinationOverride?.point;
  int get estimatedTotalMinutes =>
      _routedJourney?.totalMinutes ?? 18 + _transferMinutes + 15 + 6;
  int get totalWalkingMinutes =>
      _routedJourney?.walkingMinutes ?? _transferMinutes + 6;
  int get routeTransfers => _routedJourney?.transfers ?? 1;

  List<RoutingPlace> get journeyOrigins => _network?.places ?? const [];
  List<RoutingPlace> get journeyDestinations => _network?.places ?? const [];
  static const journeyPreferences = <String>[
    'Fastest',
    'Least walking',
    'Lowest fare',
    'Fewest transfers',
  ];

  List<BusRoute> get routeOptions {
    final seed = _seed;
    final stop = selectedStop;
    if (seed == null || stop == null) return const [];
    final routeIds = seed
        .tripsForStop(stop.id)
        .map((trip) => trip.routeId)
        .toSet();
    final routes = routeIds
        .map((id) => seed.routes[id])
        .whereType<BusRoute>()
        .toList();
    routes.sort((left, right) {
      final label = left.shortName.compareTo(right.shortName);
      return label == 0 ? left.longName.compareTo(right.longName) : label;
    });
    return routes;
  }

  BusRoute? get selectedRoute => _selectedRouteId == null || _seed == null
      ? null
      : _seed!.routes[_selectedRouteId];

  ConnectionDecision? get decision {
    final seed = _seed;
    final stop = selectedStop;
    final route = selectedRoute;
    if (seed == null || stop == null || route == null) return null;
    return adviseConnection(
      trips: seed.tripsForStop(stop.id),
      routeId: route.id,
      arrivalMinutes: _arrivalMinutes,
      transferMinutes: _transferMinutes,
    );
  }

  List<DepartureBucket> get departureBuckets {
    final stop = selectedStop;
    final seed = _seed;
    if (stop == null || seed == null) return const [];
    return List<DepartureBucket>.generate(4, (index) {
      final start = _arrivalMinutes + index * 15;
      final end = start + 15;
      final count = seed.tripsForStop(stop.id).where((trip) {
        final minutes = clockMinutes(trip.time);
        return minutes >= start && minutes < end;
      }).length;
      return DepartureBucket(label: formatClockMinutes(start), count: count);
    });
  }

  AccessLink? get accessLink {
    final hubId = _selectedHubId;
    if (_seed == null || hubId == null) return null;
    for (final link in _seed!.accessLinks) {
      if (link.hubId == hubId) return link;
    }
    return null;
  }

  Future<void> load() async {
    try {
      final loaded = await Future.wait<Object>([
        _repository.load(),
        _networkRepository.load(),
      ]);
      _seed = loaded[0] as JourneySeed;
      _network = loaded[1] as MultimodalNetwork;
      final defaultHub = _seed!.hubs.firstWhere(
        (hub) => hub.id == 'old-high-court',
        orElse: () =>
            _seed!.hubs.firstWhere((hub) => hub.supportsScheduledTransfer),
      );
      _selectHub(defaultHub);
      _recalculateRoute();
    } catch (_) {
      _error = 'The offline journey reference could not be loaded.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectHub(String hubId) {
    final hub = _seed?.hubById(hubId);
    if (hub == null) return;
    _selectHub(hub);
    _queueSync();
    notifyListeners();
  }

  void selectOrigin(String id) {
    if (!journeyOrigins.any((place) => place.id == id)) return;
    _originId = id;
    _originOverride = null;
    _recalculateRoute();
    _queueSync();
    notifyListeners();
  }

  void selectDestination(String id) {
    if (!journeyDestinations.any((place) => place.id == id)) return;
    _destinationId = id;
    _destinationOverride = null;
    _selectBestRoute();
    _recalculateRoute();
    _queueSync();
    notifyListeners();
  }

  void selectPreference(String value) {
    if (!journeyPreferences.contains(value)) return;
    _preference = value;
    _recalculateRoute();
    notifyListeners();
  }

  void selectBoardingMode(String value) {
    final mode = value == 'Any enabled service' ? null : value;
    if (mode != null && !_allowedModes.contains(mode)) return;
    _boardingMode = mode;
    _error = null;
    _recalculateRoute();
    notifyListeners();
  }

  void selectFinalMode(String value) {
    final mode = value == 'Any enabled service' ? null : value;
    if (mode != null && !_allowedModes.contains(mode)) return;
    _finalMode = mode;
    _error = null;
    _recalculateRoute();
    notifyListeners();
  }

  void toggleMode(String mode, bool enabled) {
    const supportedModes = {'Metro', 'AMTS', 'BRTS'};
    if (!supportedModes.contains(mode)) return;
    if (!enabled && _allowedModes.length == 1) {
      _error = 'Keep at least one transport mode available for routing.';
      notifyListeners();
      return;
    }
    if (enabled) {
      _allowedModes.add(mode);
    } else {
      _allowedModes.remove(mode);
      if (_boardingMode == mode) _boardingMode = null;
      if (_finalMode == mode) _finalMode = null;
    }
    _error = null;
    _recalculateRoute();
    notifyListeners();
  }

  void setMapEndpoint({
    required bool isOrigin,
    required GeoPoint point,
    bool isCurrentLocation = false,
    String? label,
  }) {
    final network = _network;
    if (network == null) return;
    final nearest = network
        .nearby(point, radiusMeters: 5000, limit: 60)
        .where(
          (node) => node.operatorName == 'AMTS/BRTS'
              ? _allowedModes.contains('AMTS') || _allowedModes.contains('BRTS')
              : _allowedModes.contains(node.operatorName),
        )
        .firstOrNull;
    final side = isOrigin ? 'start' : 'destination';
    final context = nearest == null
        ? 'map pin'
        : '${nearest.operatorName} access near ${nearest.name}';
    final place = RoutingPlace(
      id: 'map-$side',
      name:
          label ??
          '${isCurrentLocation ? 'Current location' : 'Pinned $side'} · $context',
      point: point,
    );
    if (isOrigin) {
      _originOverride = place;
    } else {
      _destinationOverride = place;
    }
    _error = null;
    _recalculateRoute();
    notifyListeners();
  }

  Future<List<LocationSearchResult>> searchLocations(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) return const [];
    final local = journeyOrigins
        .where(
          (place) => place.selectionLabel.toLowerCase().contains(normalized),
        )
        .take(8)
        .map(
          (place) => LocationSearchResult(
            name: place.selectionLabel,
            point: place.point,
            source: 'Bundled transit reference',
          ),
        )
        .toList();
    try {
      final remote = await _locationSearchRepository.search(query);
      final results = <LocationSearchResult>[...remote];
      for (final result in local) {
        final duplicate = results.any(
          (candidate) =>
              candidate.name.toLowerCase() == result.name.toLowerCase() ||
              distanceMeters(candidate.point, result.point) < 90,
        );
        if (!duplicate) results.add(result);
      }
      return results.take(8).toList();
    } catch (_) {
      return local;
    }
  }

  void _selectHub(JourneyHub hub) {
    _selectedHubId = hub.id;
    _selectedStopId = hub.candidateStops.isEmpty
        ? null
        : hub.candidateStops.first.id;
    _transferMinutes = hub.candidateStops.isEmpty
        ? 4
        : hub.candidateStops.first.estimatedTransferMinutes;
    _selectBestRoute();
  }

  String _placeName(String id) =>
      _network?.places.where((place) => place.id == id).firstOrNull?.name ?? id;

  void _recalculateRoute() {
    final network = _network;
    if (network == null) return;
    _routedJourney = _router.find(
      network: network,
      originId: _originId,
      destinationId: _destinationId,
      preference: routePreferenceFromLabel(_preference),
      allowedModes: _allowedModes,
      requiredFirstMode: _boardingMode,
      requiredFinalMode: _finalMode,
      originOverride: _originOverride,
      destinationOverride: _destinationOverride,
      scheduledDepartures: _seed?.departuresByStop ?? const {},
      departureMinutes: _arrivalMinutes,
    );
    _routeRevision++;
  }

  void selectStop(String stopId) {
    _selectedStopId = stopId;
    _transferMinutes = selectedStop?.estimatedTransferMinutes ?? 4;
    _selectBestRoute();
    _queueSync();
    notifyListeners();
  }

  void selectRoute(String routeId) {
    _selectedRouteId = routeId;
    _queueSync();
    notifyListeners();
  }

  void setArrivalTime(String value) {
    final parsed = _tryClockMinutes(value);
    if (parsed == null) {
      _error = 'Use a 24-hour time such as 17:48.';
    } else {
      _arrivalMinutes = parsed;
      _error = null;
      _selectBestRoute();
      _queueSync();
    }
    notifyListeners();
  }

  void setDepartureTime(String value) => setArrivalTime(value);

  void setTransferMinutes(double value) {
    _transferMinutes = value.round();
    _queueSync();
    notifyListeners();
  }

  void _queueSync() {
    final syncRepository = this.syncRepository;
    final uid = userId;
    final hubId = _selectedHubId;
    if (syncRepository == null || uid == null || hubId == null) return;
    unawaited(
      syncRepository.saveJourneySelection(
        uid: uid,
        hubId: hubId,
        stopId: _selectedStopId,
        routeId: _selectedRouteId,
        arrivalMinutes: _arrivalMinutes,
        transferMinutes: _transferMinutes,
      ),
    );
  }

  void _selectBestRoute() {
    final seed = _seed;
    final stop = selectedStop;
    if (seed == null || stop == null) {
      _selectedRouteId = null;
      return;
    }
    final readyAt = _arrivalMinutes + _transferMinutes;
    final candidateTrips = seed
        .tripsForStop(stop.id)
        .where((trip) => clockMinutes(trip.time) >= readyAt)
        .toList();
    final destinationHint = _destinationId == 'gujarat-university'
        ? 'gujarat university'
        : 'old high court';
    final destinationTrip = candidateTrips.cast<ScheduledTrip?>().firstWhere(
      (trip) =>
          trip != null &&
          (seed.routes[trip.routeId]?.longName.toLowerCase().contains(
                destinationHint,
              ) ??
              false),
      orElse: () => null,
    );
    final nextTrip = destinationTrip ?? candidateTrips.firstOrNull;
    _selectedRouteId = nextTrip?.routeId ?? routeOptions.firstOrNull?.id;
  }
}

int? _tryClockMinutes(String value) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class DepartureBucket {
  const DepartureBucket({required this.label, required this.count});

  final String label;
  final int count;
}
