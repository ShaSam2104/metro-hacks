import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:args/args.dart';
import 'package:csv/csv.dart';
import 'package:path/path.dart' as path;

const _usage =
    '''Prepare the compact offline journey seed from the Metro Hacks data pack.

Usage:
  dart run prepare_demo_data --data-root /path/to/metro-hacks-data

The output is an app asset containing only the selected journey hubs, nearby
scheduled transit stops, scheduled departures, and official Metro references.
''';

Future<int> runDataPrepCli(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('data-root', help: 'Root directory of metro-hacks-data.')
    ..addOption(
      'output',
      defaultsTo: 'assets/data/journey_seed.json',
      help: 'Path for the compact JSON asset.',
    )
    ..addOption(
      'radius-m',
      defaultsTo: '550',
      help: 'Maximum straight-line distance for a candidate feeder stop.',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print this usage.');

  ArgResults options;
  try {
    options = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(_usage);
    return 64;
  }

  if (options['help'] as bool) {
    stdout.write(_usage);
    return 0;
  }

  final dataRoot = options['data-root'] as String?;
  if (dataRoot == null || dataRoot.isEmpty) {
    stderr.writeln('--data-root is required.');
    stderr.writeln(_usage);
    return 64;
  }
  final radiusMeters = double.tryParse(options['radius-m'] as String? ?? '');
  if (radiusMeters == null || radiusMeters <= 0) {
    stderr.writeln('--radius-m must be a positive number.');
    return 64;
  }

  try {
    final seed = await JourneySeedBuilder(
      dataRoot: dataRoot,
      radiusMeters: radiusMeters,
    ).build();
    final output = path.normalize(options['output'] as String);
    await File(output).parent.create(recursive: true);
    await File(
      output,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(seed));
    final hubs = seed['hubs'] as List<Object?>;
    stdout.writeln('Wrote ${hubs.length} hubs to $output.');
    return 0;
  } on FileSystemException catch (error) {
    stderr.writeln('Unable to read or write a dataset file: ${error.message}');
    return 74;
  } on FormatException catch (error) {
    stderr.writeln('Dataset format error: ${error.message}');
    return 65;
  }
}

class JourneySeedBuilder {
  JourneySeedBuilder({required this.dataRoot, required this.radiusMeters});

  final String dataRoot;
  final double radiusMeters;

  Future<Map<String, Object?>> build() async {
    final stops = await _readCsv('01_transit/secondary_scraped/stops.csv');
    final allStops = stops
        .skip(1)
        .map(_TransitStop.tryFromRow)
        .whereType<_TransitStop>()
        .toList();
    final metroStops = allStops.where((stop) => stop.isMetro).toList();
    final feederStops = await _readGtfsStops();

    final hubs = <Map<String, Object?>>[];
    final candidateStopIds = <String>{};
    for (final spec in _hubSpecs) {
      final metroStop = _findMetroStop(metroStops, spec);
      if (metroStop == null) {
        hubs.add(<String, Object?>{
          'id': spec.id,
          'name': spec.name,
          'availability':
              'Metro timetable is available, but this data pack has no station coordinate for nearby-stop matching.',
          'candidateStops': const <Object?>[],
        });
        continue;
      }
      final candidates =
          feederStops
              .where((stop) => metroStop.distanceTo(stop) <= radiusMeters)
              .map(
                (stop) => <String, Object?>{
                  'id': stop.id,
                  'name': stop.name,
                  'agency': stop.agency,
                  'lat': stop.lat,
                  'lon': stop.lon,
                  'directDistanceM': metroStop.distanceTo(stop).round(),
                  'estimatedTransferMin': estimateTransferMinutes(
                    metroStop.distanceTo(stop),
                  ),
                },
              )
              .toList()
            ..sort(
              (left, right) => (left['directDistanceM']! as int).compareTo(
                right['directDistanceM']! as int,
              ),
            );
      candidateStopIds.addAll(
        candidates.map((candidate) => candidate['id']! as String),
      );
      hubs.add(<String, Object?>{
        'id': spec.id,
        'name': spec.name,
        'availability': candidates.isEmpty
            ? 'No scheduled feeder stop was found within ${radiusMeters.round()} m in the supplied GTFS feed.'
            : 'Ready for scheduled transfer guidance.',
        'metroStop': metroStop.toJson(),
        'candidateStops': candidates,
      });
    }

    final departures = await _readGtfsDepartures(candidateStopIds);
    final routeIds = departures.values
        .expand((items) => items)
        .map((item) => item['routeId']! as String)
        .toSet();
    final timetable = await _readCsv(
      '01_transit/metro/timetable/gmrc_timetable_phase2_wef_2026-05-18_tidy.csv',
    );
    final frequency = await _readCsv(
      '01_transit/metro/timetable/gmrc_line_frequency_wef_2026-05-18.csv',
    );

    return <String, Object?>{
      'schemaVersion': 1,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'transferModel': <String, Object?>{
        'walkSpeedMetersPerMinute': 60,
        'stationAccessBufferMin': 4,
        'label':
            'Conservative allowance from direct distance; adjust for the physical path and exit state.',
      },
      'sources': <String, Object?>{
        'metroTimetable': 'GMRC revised timetable w.e.f. 18.05.2026',
        'busSchedule':
            'Secondary GTFS schedule, valid 2026-09-30 to 2027-03-29',
        'serviceDisclaimer':
            'Scheduled reference only; not real-time vehicle tracking.',
      },
      'stationAccessLinks': const <Map<String, Object?>>[
        <String, Object?>{
          'hubId': 'mahatma-mandir',
          'mode': 'rail',
          'destination': 'Gandhinagar Capital Railway Station',
          'distanceM': 335,
          'description':
              'Foot over bridge with travellators, opening directly at the railway platform.',
          'source': 'GMRC Multi Model Integration page, verified 2026-10-10',
          'sourceUrl': 'https://www.gujaratmetrorail.com/mmi-2/',
        },
      ],
      'hubs': hubs,
      'busDepartures': departures,
      'busRoutes': await _readGtfsRoutes(routeIds),
      'metroPhase2Arrivals': _metroArrivalsForHubs(timetable),
      'metroLineFrequency': _records(frequency),
    };
  }

  Future<List<List<dynamic>>> _readCsv(String relativePath) async {
    final content = await File(
      path.join(dataRoot, relativePath),
    ).readAsString();
    return const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(content);
  }

  Future<List<_TransitStop>> _readGtfsStops() async {
    final archive = await _readGtfsArchive();
    final stopsFile = archive.findFile('stops.txt');
    final stopBytes = stopsFile?.readBytes();
    if (stopBytes == null) {
      throw const FormatException('GTFS zip needs a readable stops.txt.');
    }
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(utf8.decode(stopBytes));
    return rows
        .skip(1)
        .map(_TransitStop.tryFromGtfsRow)
        .whereType<_TransitStop>()
        .toList();
  }

  Future<Map<String, List<Map<String, Object?>>>> _readGtfsDepartures(
    Set<String> candidateStopIds,
  ) async {
    final archive = await _readGtfsArchive();
    final tripsFile = archive.findFile('trips.txt');
    final stopTimesFile = archive.findFile('stop_times.txt');
    if (tripsFile == null || stopTimesFile == null) {
      throw const FormatException(
        'GTFS zip needs trips.txt and stop_times.txt.',
      );
    }

    final tripBytes = tripsFile.readBytes();
    final stopTimeBytes = stopTimesFile.readBytes();
    if (tripBytes == null || stopTimeBytes == null) {
      throw const FormatException('Unable to read GTFS text files from zip.');
    }
    final trips = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(utf8.decode(tripBytes));
    final tripInfo = <String, _TripInfo>{
      for (final row in trips.skip(1))
        if (row.length >= 5)
          row[2].toString(): _TripInfo(
            routeId: row[0].toString(),
            headsign: row[3].toString(),
            directionId: row[4].toString(),
          ),
    };

    final departures = <String, List<Map<String, Object?>>>{};
    final stopTimesText = utf8.decode(stopTimeBytes);
    if (stopTimesText.contains('"')) {
      throw const FormatException(
        'Quoted GTFS stop_times rows are unsupported.',
      );
    }
    for (final line in const LineSplitter().convert(stopTimesText).skip(1)) {
      final columns = line.split(',');
      if (columns.length < 6 || !candidateStopIds.contains(columns[3])) {
        continue;
      }
      final departure = columns[2];
      final tripId = columns[0];
      final trip = tripInfo[tripId];
      if (trip == null || departure.isEmpty) {
        continue;
      }
      departures
          .putIfAbsent(columns[3], () => <Map<String, Object?>>[])
          .add(<String, Object?>{
            'time': departure,
            'routeId': trip.routeId,
            'tripId': tripId,
            'headsign': trip.headsign,
            'directionId': trip.directionId,
            'stopSequence': int.tryParse(columns[4]),
          });
    }
    for (final values in departures.values) {
      values.sort(
        (left, right) =>
            (left['time']! as String).compareTo(right['time']! as String),
      );
    }
    return departures;
  }

  Future<Map<String, Map<String, String>>> _readGtfsRoutes(
    Set<String> routeIds,
  ) async {
    final archive = await _readGtfsArchive();
    final routesFile = archive.findFile('routes.txt');
    final routeBytes = routesFile?.readBytes();
    if (routeBytes == null) {
      throw const FormatException('GTFS zip needs a readable routes.txt.');
    }
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(utf8.decode(routeBytes));
    return <String, Map<String, String>>{
      for (final row in rows.skip(1))
        if (row.length >= 5 && routeIds.contains(row[0].toString()))
          row[0].toString(): <String, String>{
            'agency': row[1].toString(),
            'shortName': row[2].toString(),
            'longName': row[3].toString(),
          },
    };
  }

  Future<Archive> _readGtfsArchive() async {
    final archiveFile = File(
      path.join(dataRoot, '01_transit/gtfs_secondary/gtfs.zip'),
    );
    return ZipDecoder().decodeBytes(await archiveFile.readAsBytes());
  }
}

int estimateTransferMinutes(double directDistanceMeters) =>
    (directDistanceMeters / 60).ceil() + 4;

List<Map<String, Object?>> _records(List<List<dynamic>> table) {
  if (table.isEmpty) return const [];
  final headers = table.first.map((value) => value.toString()).toList();
  return table.skip(1).map((row) {
    return <String, Object?>{
      for (var index = 0; index < headers.length && index < row.length; index++)
        headers[index]: row[index].toString(),
    };
  }).toList();
}

Map<String, List<Map<String, Object?>>> _metroArrivalsForHubs(
  List<List<dynamic>> timetable,
) {
  final wantedNames = _hubSpecs
      .expand((hub) => hub.names)
      .map(_normalizeName)
      .toSet();
  final arrivals = <String, List<Map<String, Object?>>>{};
  for (final record in _records(timetable)) {
    final station = record['station'] as String?;
    if (station == null || !wantedNames.contains(_normalizeName(station))) {
      continue;
    }
    arrivals.putIfAbsent(station, () => <Map<String, Object?>>[]).add(record);
  }
  return arrivals;
}

_TransitStop? _findMetroStop(List<_TransitStop> stops, _HubSpec hub) {
  final names = hub.names.map(_normalizeName).toSet();
  for (final stop in stops) {
    if (names.contains(_normalizeName(stop.name))) return stop;
  }
  return null;
}

String _normalizeName(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'\(.*?\)'), '')
    .replaceAll(RegExp(r'[^a-z0-9]'), '');

class _HubSpec {
  const _HubSpec(this.id, this.name, this.aliases);

  final String id;
  final String name;
  final Set<String> aliases;

  Iterable<String> get names => <String>{name, ...aliases};
}

const _hubSpecs = <_HubSpec>[
  _HubSpec('mahatma-mandir', 'Mahatma Mandir', {'Mahatama Mandir'}),
  _HubSpec('gnlu', 'GNLU', {}),
  _HubSpec('old-high-court', 'Old High Court', {}),
  _HubSpec('thaltej-gam', 'Thaltej Gam', {'Thaltej Metro Station'}),
  _HubSpec('vastral-gam', 'Vastral Gam', {'Vastral Gam(Metro Station)'}),
];

class _TripInfo {
  const _TripInfo({
    required this.routeId,
    required this.headsign,
    required this.directionId,
  });

  final String routeId;
  final String headsign;
  final String directionId;
}

class _TransitStop {
  const _TransitStop({
    required this.id,
    required this.agency,
    required this.name,
    required this.lat,
    required this.lon,
    required this.stopType,
  });

  static _TransitStop? tryFromRow(List<dynamic> row) {
    if (row.length < 7) {
      return null;
    }
    final lat = double.tryParse(row[3].toString());
    final lon = double.tryParse(row[4].toString());
    if (lat == null || lon == null) return null;
    return _TransitStop(
      id: row[0].toString(),
      agency: row[1].toString(),
      name: row[2].toString(),
      lat: lat,
      lon: lon,
      stopType: row[6].toString(),
    );
  }

  static _TransitStop? tryFromGtfsRow(List<dynamic> row) {
    if (row.length < 4) return null;
    final lat = double.tryParse(row[2].toString());
    final lon = double.tryParse(row[3].toString());
    if (lat == null || lon == null) return null;
    return _TransitStop(
      id: row[0].toString(),
      agency: 'scheduled-transit',
      name: row[1].toString(),
      lat: lat,
      lon: lon,
      stopType: 'SCHEDULED_TRANSIT',
    );
  }

  final String id;
  final String agency;
  final String name;
  final double lat;
  final double lon;
  final String stopType;

  bool get isMetro => agency.toLowerCase() == 'metro' || stopType == 'Metro';
  bool get isFeeder => !isMetro && lat != 0 && lon != 0;

  double distanceTo(_TransitStop other) {
    const earthRadiusMeters = 6371000.0;
    final latDelta = _radians(other.lat - lat);
    final lonDelta = _radians(other.lon - lon);
    final a =
        math.pow(math.sin(latDelta / 2), 2) +
        math.cos(_radians(lat)) *
            math.cos(_radians(other.lat)) *
            math.pow(math.sin(lonDelta / 2), 2);
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'lat': lat,
    'lon': lon,
  };
}

double _radians(double degrees) => degrees * math.pi / 180;
