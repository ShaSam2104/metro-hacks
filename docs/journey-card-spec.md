# MetroLink Journey Card

## Decision

Help a passenger answer one question while offline: given the time they expect
to reach street level, will they catch their intended scheduled bus direction?

## Primary Flow

1. Select a Metro station with a matched nearby scheduled stop.
2. Select the boarding stop and bus route/direction.
3. Enter the expected street-level arrival time and adjust the transfer buffer.
4. See the immediate scheduled trip, first catchable fallback, and the time by
   which the passenger needs to be at the stop.

## Data Contract

- All journey decisions run from `assets/data/journey_seed.json`.
- AMTS/BRTS/GTSL times are cached schedules, never real-time predictions.
- The transfer buffer is an editable allowance, not a promised walking route.
- Mahatma Mandir exposes a separate verified Metro-to-rail access link rather
  than an unsupported bus connection.

## Demo Stations

- Old High Court: default station and strongest end-to-end bus case.
- Thaltej Gam and Vastral Gam: additional scheduled transfer cases.
- Mahatma Mandir: verified link to Gandhinagar Capital Railway Station.

## Offline Rule

The app must launch, load the journey seed, and produce a connection decision
in airplane mode. Firebase is not part of the critical path.
# PS-08 Alignment

MetroLink is the working prototype for **PS-08 One City, One Journey**. Its
current sample joins a Metro arrival to a scheduled AMTS leg, shows the
transfer allowance, and presents a transparent fare estimate with a leg-based
settlement proposal. Current BRTS timetable data is not in the offline seed, so
BRTS is explicitly shown as the next data integration rather than a fabricated
schedule.
