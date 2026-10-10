import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../domain/models/multimodal_network.dart';
import '../../../../domain/models/location_search_result.dart';
import '../../../../domain/use_cases/multimodal_router.dart';
import '../view_models/journey_card_view_model.dart';

class JourneyRouteCard extends StatelessWidget {
  const JourneyRouteCard({
    super.key,
    required this.viewModel,
    this.expandedMap = false,
  });
  final JourneyCardViewModel viewModel;
  final bool expandedMap;

  @override
  Widget build(BuildContext context) {
    final journey = viewModel.routedJourney;
    final theme = ShadTheme.of(context);
    if (journey == null) {
      return ShadCard(
        title: Text('No offline route found', style: theme.textTheme.h4),
        description: const Text(
          'Choose places within the bundled Ahmedabad network reference.',
        ),
      );
    }
    return ShadCard(
          title: Text(
            '${journey.totalMinutes} min route',
            style: theme.textTheme.h4,
          ),
          description: Text(
            '${journey.walkingMinutes} min walking · ${journey.transfers} transfer${journey.transfers == 1 ? '' : 's'} · ${journey.scheduledWaitMinutes > 0 ? '${journey.scheduledWaitMinutes} min scheduled wait' : 'offline timing estimate'} · estimated Rs ${journey.estimatedFare}',
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final sideBySide = expandedMap && constraints.maxWidth >= 740;
              final itinerary = _Itinerary(journey: journey);
              final map = SizedBox(
                height: expandedMap ? 540 : 330,
                child: _PassengerRouteMap(
                  journey: journey,
                  viewModel: viewModel,
                ),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (sideBySide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: map),
                        const SizedBox(width: 16),
                        SizedBox(width: 270, child: itinerary),
                      ],
                    )
                  else ...[
                    map,
                    const SizedBox(height: 14),
                    itinerary,
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Bundled AMTS/BRTS and Metro network. GTFS departures are applied where timetable coverage exists; route geometry and fare remain estimates.',
                    style: theme.textTheme.muted,
                  ),
                ],
              );
            },
          ),
        )
        .animate(key: ValueKey('route-${viewModel.routeRevision}'))
        .fadeIn(duration: 240.ms)
        .slideY(begin: .02);
  }
}

class _Itinerary extends StatelessWidget {
  const _Itinerary({required this.journey});
  final RoutedJourney journey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: journey.legs.indexed
        .map((entry) => _LegRow(leg: entry.$2, index: entry.$1))
        .toList(),
  );
}

class _PassengerRouteMap extends StatefulWidget {
  const _PassengerRouteMap({required this.journey, required this.viewModel});
  final RoutedJourney journey;
  final JourneyCardViewModel viewModel;

  @override
  State<_PassengerRouteMap> createState() => _PassengerRouteMapState();
}

class _PassengerRouteMapState extends State<_PassengerRouteMap> {
  late final Future<List<_PassengerStop>> _baseline = _loadBaseline();
  final MapController _mapController = MapController();
  final TextEditingController _placeSearch = TextEditingController();
  var _showNetwork = false;
  var _isPickingOrigin = true;
  var _isLocating = false;
  var _isSearching = false;
  String? _locationMessage;
  List<LocationSearchResult> _searchResults = const [];

  @override
  void dispose() {
    _placeSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final journey = widget.journey;
    final points = journey.legs
        .expand((leg) => leg.points)
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();
    final center = points.isEmpty
        ? const LatLng(23.03, 72.59)
        : points[points.length ~/ 2];
    return FutureBuilder<List<_PassengerStop>>(
      future: _baseline,
      builder: (context, snapshot) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 13,
                onTap: (_, point) => _pinMapPoint(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.metrolink.metro_hacks',
                ),
                if (_showNetwork && snapshot.hasData)
                  CircleLayer(
                    circles: snapshot.data!
                        .map(
                          (stop) => CircleMarker(
                            point: LatLng(stop.latitude, stop.longitude),
                            radius: stop.operatorName == 'Metro' ? 3 : 1.7,
                            color: _networkColor(
                              stop.operatorName,
                            ).withValues(alpha: .55),
                          ),
                        )
                        .toList(),
                  ),
                PolylineLayer(
                  polylines: journey.legs
                      .where((leg) => leg.points.length > 1)
                      .map(
                        (leg) => Polyline(
                          points: leg.points
                              .map(
                                (point) =>
                                    LatLng(point.latitude, point.longitude),
                              )
                              .toList(),
                          color: _modeColor(leg.mode),
                          strokeWidth: leg.isWalking ? 2 : 5,
                          pattern: leg.isWalking
                              ? const StrokePattern.dotted(spacingFactor: 2)
                              : const StrokePattern.solid(),
                        ),
                      )
                      .toList(),
                ),
                MarkerLayer(
                  markers: [
                    if (points.isNotEmpty)
                      Marker(
                        point: points.first,
                        width: 30,
                        height: 30,
                        child: const _EndpointMarker(
                          icon: Icons.trip_origin_rounded,
                          color: Color(0xff2e7d32),
                        ),
                      ),
                    if (points.length > 1)
                      Marker(
                        point: points.last,
                        width: 30,
                        height: 30,
                        child: const _EndpointMarker(
                          icon: Icons.location_on_rounded,
                          color: Color(0xffc62828),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 9,
              right: 9,
              child: _MapControlSurface(
                child: ShadButton.outline(
                  onPressed: () => setState(() => _showNetwork = !_showNetwork),
                  child: Text(_showNetwork ? 'Route only' : 'Network map'),
                ),
              ),
            ),
            Positioned(
              top: 9,
              left: 9,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 270),
                child: _MapControlSurface(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ShadInput(
                              controller: _placeSearch,
                              placeholder: const Text('Search Ahmedabad place'),
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _searchLocations(),
                            ),
                          ),
                          const SizedBox(width: 6),
                          ShadButton.outline(
                            onPressed: _isSearching ? null : _searchLocations,
                            child: _isSearching
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.search_rounded, size: 17),
                          ),
                        ],
                      ),
                      if (_searchResults.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        ..._searchResults.map(
                          (result) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: SizedBox(
                              width: double.infinity,
                              child: ShadButton.outline(
                                onPressed: () => _chooseSearchResult(result),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '${result.name} · ${result.source}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ShadButton.outline(
                            onPressed: () =>
                                setState(() => _isPickingOrigin = true),
                            child: Text(
                              _isPickingOrigin ? 'Setting start' : 'Set start',
                            ),
                          ),
                          ShadButton.outline(
                            onPressed: () =>
                                setState(() => _isPickingOrigin = false),
                            child: Text(
                              _isPickingOrigin
                                  ? 'Set destination'
                                  : 'Setting destination',
                            ),
                          ),
                          ShadButton.outline(
                            onPressed: _isLocating ? null : _useCurrentLocation,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_isLocating)
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.my_location_outlined,
                                    size: 16,
                                  ),
                                const SizedBox(width: 6),
                                const Text('My location'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          _locationMessage ??
                              'Tap the map to set ${_isPickingOrigin ? 'your start' : 'your destination'}.',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pinMapPoint(LatLng point) {
    widget.viewModel.setMapEndpoint(
      isOrigin: _isPickingOrigin,
      point: GeoPoint(point.latitude, point.longitude),
    );
    setState(() {
      _locationMessage =
          '${_isPickingOrigin ? 'Start' : 'Destination'} pinned. Routing to the nearest selected service.';
    });
    _mapController.move(point, 14.5);
  }

  Future<void> _searchLocations() async {
    final query = _placeSearch.text.trim();
    if (query.length < 2) {
      setState(() {
        _searchResults = const [];
        _locationMessage = 'Enter at least two letters to search Ahmedabad.';
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _locationMessage = 'Searching Ahmedabad places and bundled stops...';
    });
    final results = await widget.viewModel.searchLocations(query);
    if (!mounted) return;
    setState(() {
      _isSearching = false;
      _searchResults = results;
      _locationMessage = results.isEmpty
          ? 'No match found. Try a landmark, locality, or nearby stop.'
          : 'Choose a result for your ${_isPickingOrigin ? 'start' : 'destination'}.';
    });
  }

  void _chooseSearchResult(LocationSearchResult result) {
    widget.viewModel.setMapEndpoint(
      isOrigin: _isPickingOrigin,
      point: result.point,
      label: result.name,
    );
    _mapController.move(
      LatLng(result.point.latitude, result.point.longitude),
      15,
    );
    setState(() {
      _placeSearch.clear();
      _searchResults = const [];
      _locationMessage =
          '${_isPickingOrigin ? 'Start' : 'Destination'} set to ${result.name}.';
    });
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _isLocating = true;
      _locationMessage = 'Finding your location...';
    });
    try {
      if (!kIsWeb) {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          throw StateError('Location permission was not granted.');
        }
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      widget.viewModel.setMapEndpoint(
        isOrigin: true,
        isCurrentLocation: true,
        point: GeoPoint(position.latitude, position.longitude),
      );
      _mapController.move(LatLng(position.latitude, position.longitude), 14.5);
      if (!mounted) return;
      setState(() {
        _isPickingOrigin = false;
        _locationMessage = 'Current location set as your start.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locationMessage = kIsWeb
            ? 'Browser location was blocked. Allow location for this site, then try again.'
            : 'Location unavailable. Allow location permission, then try again.';
      });
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<List<_PassengerStop>> _loadBaseline() async {
    final decoded =
        jsonDecode(
              await rootBundle.loadString('assets/data/network_baseline.json'),
            )
            as Map<String, dynamic>;
    return (decoded['stops'] as List).whereType<Map>().map((item) {
      final stop = Map<String, dynamic>.from(item);
      return _PassengerStop(
        operatorName: stop['operator'] as String,
        latitude: (stop['latitude'] as num).toDouble(),
        longitude: (stop['longitude'] as num).toDouble(),
      );
    }).toList();
  }
}

class _MapControlSurface extends StatelessWidget {
  const _MapControlSurface({required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding ?? const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: const Color(0xff111827).withValues(alpha: .94),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Colors.white.withValues(alpha: .55)),
      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8)],
    ),
    child: child,
  );
}

class _PassengerStop {
  const _PassengerStop({
    required this.operatorName,
    required this.latitude,
    required this.longitude,
  });
  final String operatorName;
  final double latitude;
  final double longitude;
}

class _EndpointMarker extends StatelessWidget {
  const _EndpointMarker({required this.icon, required this.color});
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    duration: const Duration(milliseconds: 420),
    curve: Curves.easeOutBack,
    tween: Tween(begin: .45, end: 1),
    builder: (context, scale, child) =>
        Transform.scale(scale: scale, child: child),
    child: Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 21),
    ),
  );
}

class _LegRow extends StatelessWidget {
  const _LegRow({required this.leg, required this.index});
  final RouteLeg leg;
  final int index;
  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final label = leg.isWalking
        ? 'Walk'
        : '${leg.mode} · ${leg.route?.shortName ?? ''}';
    return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 27,
                height: 27,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _modeColor(leg.mode).withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Icon(
                  leg.isWalking
                      ? Icons.directions_walk_outlined
                      : leg.mode == 'Metro'
                      ? Icons.train_outlined
                      : Icons.directions_bus_outlined,
                  size: 16,
                  color: _modeColor(leg.mode),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.small),
                    const SizedBox(height: 2),
                    Text(
                      '${leg.from} to ${leg.to}',
                      style: theme.textTheme.muted,
                    ),
                  ],
                ),
              ),
              Text('${leg.minutes} min', style: theme.textTheme.small),
            ],
          ),
        )
        .animate(delay: (70 * index).ms)
        .fadeIn(duration: 200.ms)
        .slideX(begin: .02);
  }
}

Color _modeColor(String mode) => switch (mode) {
  'Metro' => const Color(0xff1976d2),
  'BRTS' => const Color(0xfff57c00),
  'AMTS' => const Color(0xff00897b),
  _ => const Color(0xff6b7280),
};

Color _networkColor(String operatorName) => switch (operatorName) {
  'Metro' => const Color(0xff1976d2),
  'BRTS' => const Color(0xfff57c00),
  _ => const Color(0xff00897b),
};
