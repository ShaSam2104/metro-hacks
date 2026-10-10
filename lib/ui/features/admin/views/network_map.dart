import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter/services.dart';

import '../../../../data/repositories/transit_reference_repository.dart';

class NetworkMap extends StatefulWidget {
  const NetworkMap({
    super.key,
    required this.references,
    required this.onMapTap,
  });

  final List<TransitReferenceItem> references;
  final ValueChanged<LatLng> onMapTap;

  @override
  State<NetworkMap> createState() => _NetworkMapState();
}

class _NetworkMapState extends State<NetworkMap> {
  late final Future<_NetworkBaseline> _baseline = _NetworkBaseline.load();

  @override
  Widget build(BuildContext context) => FutureBuilder<_NetworkBaseline>(
    future: _baseline,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return _NetworkMapCanvas(
        references: widget.references,
        baseline: snapshot.data!,
        onMapTap: widget.onMapTap,
      );
    },
  );
}

class _NetworkMapCanvas extends StatelessWidget {
  const _NetworkMapCanvas({
    required this.references,
    required this.baseline,
    required this.onMapTap,
  });

  final List<TransitReferenceItem> references;
  final _NetworkBaseline baseline;
  final ValueChanged<LatLng> onMapTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: const LatLng(23.027, 72.59),
              initialZoom: 12.2,
              minZoom: 10,
              onTap: (_, point) => onMapTap(point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.metrolink.metro_hacks',
              ),
              CircleLayer(
                circles: baseline.stops
                    .map(
                      (stop) => CircleMarker(
                        point: LatLng(stop.latitude, stop.longitude),
                        radius: stop.operatorName == 'Metro' ? 3.6 : 2.2,
                        color: _baselineColor(
                          stop.operatorName,
                        ).withValues(alpha: .63),
                        borderColor: Colors.white.withValues(alpha: .55),
                        borderStrokeWidth: .45,
                      ),
                    )
                    .toList(),
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _blueLine,
                    color: const Color(0xff1976d2),
                    strokeWidth: 4,
                  ),
                  ..._routePolylines(references),
                ],
              ),
              MarkerLayer(
                markers: [
                  ..._blueLineStations.map(
                    (station) => Marker(
                      point: station.point,
                      width: 26,
                      height: 26,
                      child: Tooltip(
                        message: station.name,
                        child: const _StationMarker(color: Color(0xff1976d2)),
                      ),
                    ),
                  ),
                  ..._referenceMarkers(references),
                ],
              ),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 12,
            left: 12,
            child: _MapLegend(
              color: theme.colorScheme.background,
              baseline: baseline,
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.background.withValues(alpha: .92),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                'Tap map to set station coordinates',
                style: theme.textTheme.small,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.color, required this.baseline});
  final Color color;
  final _NetworkBaseline baseline;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Imported operational baseline'),
        const SizedBox(height: 3),
        Text(
          'Metro ${baseline.count('Metro')}  |  AMTS ${baseline.count('AMTS')}  |  BRTS ${baseline.count('BRTS')}',
        ),
        const SizedBox(height: 3),
        const Text('Blue Line corridor: Thaltej Gam - Vastral Gam'),
        const SizedBox(height: 3),
        const Text('Reference data is read-only'),
      ],
    ),
  );
}

class _StationMarker extends StatelessWidget {
  const _StationMarker({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      border: Border.all(color: color, width: 3),
    ),
    child: Icon(Icons.train_outlined, size: 14, color: color),
  );
}

List<Marker> _referenceMarkers(List<TransitReferenceItem> references) =>
    references
        .where((item) => item.entityType == 'station')
        .map((item) {
          final latitude = item.payload['latitude'];
          final longitude = item.payload['longitude'];
          if (latitude is! num || longitude is! num) return null;
          final isClosed = item.status == 'closed';
          final color = isClosed ? Colors.red.shade700 : Colors.teal.shade700;
          return Marker(
            point: LatLng(latitude.toDouble(), longitude.toDouble()),
            width: 30,
            height: 30,
            child: Tooltip(
              message: '${item.title} (${item.status})',
              child: _StationMarker(color: color),
            ),
          );
        })
        .whereType<Marker>()
        .toList();

List<Polyline> _routePolylines(List<TransitReferenceItem> references) =>
    references
        .where((item) => item.entityType == 'route')
        .map((item) {
          final geometry = item.payload['geometry'];
          if (geometry is! List) return null;
          final points = geometry
              .whereType<Map>()
              .map((point) {
                final latitude = point['latitude'];
                final longitude = point['longitude'];
                return latitude is num && longitude is num
                    ? LatLng(latitude.toDouble(), longitude.toDouble())
                    : null;
              })
              .whereType<LatLng>()
              .toList();
          if (points.length < 2) return null;
          return Polyline(
            points: points,
            color: item.operatorName == 'BRTS'
                ? const Color(0xfff57c00)
                : const Color(0xff00897b),
            strokeWidth: 3,
          );
        })
        .whereType<Polyline>()
        .toList();

class NetworkStation {
  const NetworkStation(this.name, this.latitude, this.longitude);
  final String name;
  final double latitude;
  final double longitude;
  LatLng get point => LatLng(latitude, longitude);
}

const _blueLineStations = [
  NetworkStation('Vastral Gam', 22.99723908320867, 72.66747041572408),
  NetworkStation('Nirant Cross Road', 22.999863263480865, 72.65888489671117),
  NetworkStation('Vastral', 23.003594691685002, 72.6476768142666),
  NetworkStation('Rabari Colony', 23.005542671311495, 72.63549394881706),
  NetworkStation('Amraiwadi', 23.007763993796566, 72.62878346307075),
  NetworkStation('Apparel Park', 23.010719725226565, 72.61816883538819),
  NetworkStation('Kankaria East', 23.014773992937037, 72.60693552603419),
  NetworkStation('Kalupur Metro Station', 23.02477887132399, 72.6029083880447),
  NetworkStation('Gheekanta', 23.02859425164894, 72.58683730138765),
  NetworkStation('Shahpur', 23.039191985120183, 72.5812443430793),
  NetworkStation('Old High Court', 23.03744440876014, 72.56701000166855),
  NetworkStation('Stadium', 23.03984049870335, 72.56180665079206),
  NetworkStation('Commerce Six Road', 23.040721303939534, 72.55302496018233),
  NetworkStation('Gujarat University', 23.04486062790798, 72.5436240789925),
  NetworkStation('Gurukul Road', 23.04593980470685, 72.53509879782438),
  NetworkStation('Doordarshan Kendra', 23.048217078771085, 72.5247565213341),
  NetworkStation('Thaltej Gam', 23.049821545405166, 72.51608014554085),
];

final _blueLine = _blueLineStations.map((station) => station.point).toList();

Color _baselineColor(String operatorName) => switch (operatorName) {
  'Metro' => const Color(0xff1976d2),
  'BRTS' => const Color(0xfff57c00),
  _ => const Color(0xff00897b),
};

class _NetworkBaseline {
  const _NetworkBaseline({required this.stops, required this.counts});
  final List<_BaselineStop> stops;
  final Map<String, int> counts;

  int count(String operatorName) => counts[operatorName] ?? 0;

  static Future<_NetworkBaseline> load() async {
    final decoded =
        jsonDecode(
              await rootBundle.loadString('assets/data/network_baseline.json'),
            )
            as Map<String, dynamic>;
    final metadata = decoded['metadata'] as Map<String, dynamic>;
    return _NetworkBaseline(
      stops: (decoded['stops'] as List)
          .whereType<Map>()
          .map(
            (stop) => _BaselineStop.fromJson(Map<String, dynamic>.from(stop)),
          )
          .toList(),
      counts: (metadata['counts'] as Map).map(
        (key, value) => MapEntry(key as String, value as int),
      ),
    );
  }
}

class _BaselineStop {
  const _BaselineStop({
    required this.operatorName,
    required this.latitude,
    required this.longitude,
  });
  final String operatorName;
  final double latitude;
  final double longitude;
  factory _BaselineStop.fromJson(Map<String, dynamic> json) => _BaselineStop(
    operatorName: json['operator'] as String,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
  );
}
