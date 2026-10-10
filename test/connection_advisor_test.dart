import 'package:flutter_test/flutter_test.dart';
import 'package:metro_hacks/domain/models/journey_data.dart';
import 'package:metro_hacks/domain/use_cases/connection_advisor.dart';

void main() {
  const trips = <ScheduledTrip>[
    ScheduledTrip(
      time: '17:55:00',
      routeId: 'a',
      tripId: 'first',
      headsign: 'A',
    ),
    ScheduledTrip(
      time: '18:15:00',
      routeId: 'a',
      tripId: 'second',
      headsign: 'A',
    ),
  ];

  test('shows the first catchable trip after the transfer allowance', () {
    final decision = adviseConnection(
      trips: trips,
      routeId: 'a',
      arrivalMinutes: 17 * 60 + 48,
      transferMinutes: 7,
    );

    expect(decision.nextScheduled?.tripId, 'first');
    expect(decision.firstCatchable?.tripId, 'first');
    expect(decision.missesNext, isFalse);
  });

  test('identifies a missed immediate trip and its fallback', () {
    final decision = adviseConnection(
      trips: trips,
      routeId: 'a',
      arrivalMinutes: 17 * 60 + 50,
      transferMinutes: 7,
    );

    expect(decision.nextScheduled?.tripId, 'first');
    expect(decision.firstCatchable?.tripId, 'second');
    expect(decision.missesNext, isTrue);
  });
}
