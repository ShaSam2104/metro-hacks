import 'package:flutter_test/flutter_test.dart';

import 'package:metro_hacks/data/repositories/multimodal_network_repository.dart';
import 'package:metro_hacks/domain/models/journey_data.dart';
import 'package:metro_hacks/domain/models/multimodal_network.dart';
import 'package:metro_hacks/domain/use_cases/multimodal_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('routes between bundled Ahmedabad locations offline', () async {
    final network = await const MultimodalNetworkRepository().load();
    final journey = const MultimodalRouter().find(
      network: network,
      originId: 'thaltej-gam',
      destinationId: 'vastral-gam',
      preference: RoutePreference.fastest,
    );

    expect(network.nodes.length, greaterThan(3000));
    expect(journey, isNotNull);
    expect(journey!.legs, isNotEmpty);
    expect(journey.totalMinutes, greaterThan(0));
  });

  test('uses an AMTS or BRTS leg for an off-corridor destination', () async {
    final network = await const MultimodalNetworkRepository().load();
    final journey = const MultimodalRouter().find(
      network: network,
      originId: 'thaltej-gam',
      destinationId: 'bopal-gam',
      preference: RoutePreference.fastest,
    );

    expect(journey, isNotNull);
    expect(
      journey!.legs.any((leg) => leg.mode == 'AMTS' || leg.mode == 'BRTS'),
      isTrue,
    );
  });

  test('honours a passenger bus-only travel choice', () async {
    final network = await const MultimodalNetworkRepository().load();
    final journey = const MultimodalRouter().find(
      network: network,
      originId: 'thaltej-gam',
      destinationId: 'bopal-gam',
      preference: RoutePreference.fastest,
      allowedModes: const {'AMTS', 'BRTS'},
    );

    expect(journey, isNotNull);
    expect(journey!.legs.any((leg) => leg.mode == 'Metro'), isFalse);
    expect(
      journey.legs.any((leg) => leg.mode == 'AMTS' || leg.mode == 'BRTS'),
      isTrue,
    );
  });

  test('routes from a passenger-pinned map location', () async {
    final network = await const MultimodalNetworkRepository().load();
    final journey = const MultimodalRouter().find(
      network: network,
      originId: 'thaltej-gam',
      destinationId: 'bopal-gam',
      preference: RoutePreference.fastest,
      originOverride: const RoutingPlace(
        id: 'passenger-pin',
        name: 'Pinned start',
        point: GeoPoint(23.0574, 72.5207),
      ),
    );

    expect(journey, isNotNull);
    expect(journey!.legs.first.from, 'Pinned start');
  });

  test('accounts for a published departure when timetable coverage exists', () {
    const origin = RoutingPlace(
      id: 'origin',
      name: 'Origin',
      point: GeoPoint(23.0, 72.0),
    );
    const destination = RoutingPlace(
      id: 'destination',
      name: 'Destination',
      point: GeoPoint(23.03, 72.0),
    );
    final network = MultimodalNetwork(
      places: const [origin, destination],
      nodes: const {
        'a': TransitNode(
          id: 'a',
          name: 'Start stop',
          point: GeoPoint(23.0, 72.0),
          operatorName: 'AMTS',
        ),
        'b': TransitNode(
          id: 'b',
          name: 'End stop',
          point: GeoPoint(23.03, 72.0),
          operatorName: 'AMTS',
        ),
      },
      routes: const {
        'r1': TransitRoute(
          id: 'r1',
          operatorName: 'AMTS',
          shortName: '1',
          longName: 'Test route',
        ),
      },
      edges: const [
        TransitEdge(
          fromId: 'a',
          toId: 'b',
          routeId: 'r1',
          mode: 'AMTS',
          minutes: 10,
        ),
      ],
    );

    final journey = const MultimodalRouter().find(
      network: network,
      originId: 'origin',
      destinationId: 'destination',
      preference: RoutePreference.fastest,
      departureMinutes: 10 * 60,
      scheduledDepartures: const {
        'a': [
          ScheduledTrip(
            time: '10:10',
            routeId: 'r1',
            tripId: 'trip-1',
            headsign: 'End stop',
          ),
        ],
      },
    );

    expect(journey, isNotNull);
    expect(journey!.scheduledWaitMinutes, 9);
  });
}
