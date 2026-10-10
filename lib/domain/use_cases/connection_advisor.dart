import '../models/journey_data.dart';

class ConnectionDecision {
  const ConnectionDecision({
    required this.readyAtMinutes,
    required this.nextScheduled,
    required this.firstCatchable,
  });

  final int readyAtMinutes;
  final ScheduledTrip? nextScheduled;
  final ScheduledTrip? firstCatchable;

  bool get hasService => firstCatchable != null;
  bool get missesNext =>
      nextScheduled != null &&
      clockMinutes(nextScheduled!.time) < readyAtMinutes;
}

ConnectionDecision adviseConnection({
  required List<ScheduledTrip> trips,
  required String routeId,
  required int arrivalMinutes,
  required int transferMinutes,
}) {
  final routeTrips = trips.where((trip) => trip.routeId == routeId).toList()
    ..sort(
      (left, right) =>
          clockMinutes(left.time).compareTo(clockMinutes(right.time)),
    );
  final readyAt = arrivalMinutes + transferMinutes;
  final nextScheduled = routeTrips.cast<ScheduledTrip?>().firstWhere(
    (trip) => clockMinutes(trip!.time) >= arrivalMinutes,
    orElse: () => null,
  );
  final firstCatchable = routeTrips.cast<ScheduledTrip?>().firstWhere(
    (trip) => clockMinutes(trip!.time) >= readyAt,
    orElse: () => null,
  );
  return ConnectionDecision(
    readyAtMinutes: readyAt,
    nextScheduled: nextScheduled,
    firstCatchable: firstCatchable,
  );
}

int clockMinutes(String time) {
  final parts = time.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

String formatClockMinutes(int minutes) {
  final normalized = minutes % (24 * 60);
  final hour = normalized ~/ 60;
  final minute = normalized % 60;
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
