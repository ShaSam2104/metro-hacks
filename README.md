# MetroLink - Metro Hacks Submission

MetroLink is an offline-capable Ahmedabad multimodal journey planner for the
City Public Transport track. It plans a passenger route across Metro, AMTS and
BRTS, lets a passenger select a start/destination on the map or from search,
and gives operators a separate network-control workspace.

## Run Locally

Prerequisites: Flutter 3.44+ and a Chrome-based browser. Python 3.12 and Docker
are needed only when running the FastAPI backend locally.

```sh
cd /Users/shasam/Dev/metro_hacks
flutter pub get
flutter run -d chrome \
  --dart-define=API_BASE_URL=https://api.92.4.65.123.sslip.io
```

For a browser-only debug server, use:

```sh
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080 \
  --dart-define=API_BASE_URL=https://api.92.4.65.123.sslip.io
```

Open `http://127.0.0.1:8080`. Browser location permission works on localhost
and HTTPS hosts; use the map pin if permission is denied.

## Evaluator Build

The deployed submission is available at:

- Frontend: `https://app.92.4.65.123.sslip.io`
- API health: `https://api.92.4.65.123.sslip.io/health`

The passenger flow is deliberately offline-first: bundled reference data powers
Metro/AMTS/BRTS routing and map selection even if the API is unavailable. An
authenticated account adds server-backed selection sync and a demo journey-pass
wallet. The PDF QR is an order reference for the prototype, not a valid metro
gate ticket or payment confirmation.

## Key Flows

- Passenger: search an Ahmedabad place through OpenStreetMap, choose a bundled
  Metro/AMTS/BRTS stop, or use a map/current-location pin for either endpoint.
  The app routes that coordinate to the selected services and displays the map,
  route legs and fare estimate.
- Passenger: set a leave time. The planner includes timetable wait time for
  GTFS-covered AMTS/BRTS boarding points and otherwise labels travel timing as
  an offline estimate.
- Passenger: issue an immediate demo journey pass for self or another named
  rider; orders are account-owned and downloadable as QR PDFs.
- Operator: sign in with an operator account to manage stations, AMTS/BRTS
  corridors, coordinates and map geometry. The operator UI does not switch
  roles; logout returns to sign-in.

## Verification

```sh
flutter analyze
flutter test
flutter build web \
  --dart-define=API_BASE_URL=https://api.92.4.65.123.sslip.io
```

## Backend

The FastAPI service is in [`backend/`](backend/) and is documented in
[`backend/README.md`](backend/README.md). To run it locally:

```sh
cd backend
cp .env.example .env
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
set -a; source .env; set +a
export METROLINK_DATABASE_PATH="$PWD/.local/metrolink.db"
uvicorn app.main:app --reload
```

## Data Notes

The app uses a bundled, processed subset of the provided Metro Hacks transit
data. It is an offline reference graph rather than live vehicle tracking. The
bundled GTFS timetable contains 7,138 departures across 238 AMTS/BRTS routes at
22 covered transfer stops; those waits are applied only where a selected route
and stop have a matching published departure. OpenStreetMap place search is an
online enhancement through the backend, while bundled landmarks and stops keep
search usable in airplane mode. Route geometry, fares, and uncovered service
timing remain prototype estimates and are labelled as such.

For fares, the supplied data includes GMRC's official 1,378-pair Metro token
fare matrix. The compact offline graph currently bundles only the Blue Line,
so Metro remains a conservative distance-band estimate until the full
station-to-station matrix is integrated. No official AMTS/BRTS fare chart was
available in the supplied data; their fallback is transparently shown as Rs
2/km, with a Rs 5 minimum and Rs 30 cap.

The implemented passenger experience is documented in
[`docs/journey-card-spec.md`](docs/journey-card-spec.md).

## Architecture

- `domain/`: track-neutral models and capability profiles.
- `data/`: offline reference loading and synchronization boundaries.
- `ui/`: feature-oriented views and view models.

The app starts as a neutral workbench. A revealed problem is represented as a
`ChallengeBrief`, then its track profile enables only the reusable capabilities
it needs: offline capture, recommendations, advisories, evidence, and sync.

## Planned Data Boundaries

- The packaged seed supplies deterministic journey decisions with no network.
- A self-hosted FastAPI service on the OCI VM owns accounts, selections, and
  controlled operational advisories when online.
- The next mobile integration change will queue passenger-owned mutations
  locally and synchronize them through the API when connectivity is back.

The active backend contract and extension rules live in
[`docs/backend.md`](docs/backend.md). The deployable service is in
[`backend/`](backend/).

## Offline Journey Seed

`assets/data/journey_seed.json` is a generated, 800 KB offline reference asset
for the passenger journey-card prototype. It contains only:

- official GMRC timetable and frequency references;
- GTFS scheduled departures for nearby stops at Old High Court, Thaltej Gam,
  and Vastral Gam;
- the GTFS route labels needed to present those departures; and
- route direction and headsign data, so a passenger can pick the bus they
  actually intend to board;
- conservative transfer allowances based on direct distance, 60 m/min walking,
  and a four-minute station-access buffer.

Regenerate it after updating the source pack:

```sh
dart run metro_hacks:prepare_demo_data \
  --data-root /Users/shasam/Downloads/metro-hacks-data
```

The seed deliberately does not imply live tracking. Mahatma Mandir remains a
Metro-timetable reference only because the provided pack has no coordinate for
nearby-stop matching, and GNLU has no GTFS feeder stop within 550 m. The
prototype should default to Old High Court, Thaltej Gam, or Vastral Gam for a
complete "will I make it?" demonstration.

The passenger flow is intentionally narrow: select the station, tell the app
when you expect to reach street level, select a scheduled route/direction, and
get the first catchable trip and its fallback. Direct distance is not a walking
route, so the interface must present the allowance as adjustable rather than
claiming an exact path or live arrival time.

Mahatma Mandir is a separate, well-evidenced Metro-to-rail transfer: GMRC
documents a 335 m foot-over bridge with travellators directly to Gandhinagar
Capital Railway Station. The generated seed exposes this as an `accessLink`,
not as an invented bus connection.
