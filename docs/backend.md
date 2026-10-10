# MetroLink Backend Specification

## Purpose

MetroLink is offline first: bundled journey data and the connection decision are
the demonstration-critical path. The OCI-hosted FastAPI service is the system
of record for accounts, journey-selection synchronization, and service
advisories once connectivity returns. Firebase is not on the required path.

## Architecture

```text
Flutter Android
  |-- bundled JSON journey seed -> works in airplane mode
  `-- HTTPS -> FastAPI on OCI VM -> SQLite Docker volume
                                      |-- users and Argon2 password hashes
                                      |-- hashed, rotating refresh tokens
                                      |-- current journey selections
                                      `-- service advisories
```

The API uses short-lived signed JWT access tokens and rotating refresh tokens.
The client only needs an `API_BASE_URL` build-time setting once a public HTTPS
hostname has been configured for the VM.

## Data ownership

| Resource | Endpoint | Caller | Notes |
| --- | --- | --- | --- |
| Account | `/v1/auth/register`, `/login`, `/refresh` | Passenger | Passwords are never returned or stored in plain text. |
| Current selection | `GET`, `PUT /v1/journey-selection` | Same authenticated passenger | One record per account; offline client changes should queue locally. |
| Advisory read | `GET /v1/service-advisories` | Anyone | Only unexpired records are returned. |
| Advisory publication | `POST /v1/service-advisories` | Operator | Stored server role is verified per request. |

## API contracts

### Register and login

Both endpoints accept:

```json
{ "username": "metro_user", "password": "at-least-ten-characters" }
```

They return an access token and a refresh token. The Android client must store
the refresh token in platform-secure storage, never in source code or logs.

### Journey selection

```json
{
  "hub_id": "old-high-court",
  "stop_id": "1234",
  "route_id": "45",
  "arrival_minutes": 1068,
  "transfer_minutes": 8
}
```

The server derives `updated_at` and the user identity from the access token;
neither is supplied by a client.

### Service advisory

```json
{
  "station_id": "old-high-court",
  "severity": "minor",
  "message": "Exit B is temporarily unavailable.",
  "expires_at": "2026-10-10T18:00:00Z"
}
```

Only the exact server-side `operator` role may publish. Role elevation has no
public endpoint: the VM administrator runs the documented local command.

## Extension rules

1. Add a feature as a new router/module, with a request schema and an explicit
   authorization decision before connecting Flutter UI.
2. Keep all trusted derivation, timestamps, roles, and write validation server
   side.
3. Preserve offline usefulness. A network endpoint may enhance a journey card,
   but cannot be required to show the scheduled fallback.
4. Version breaking endpoint changes under `/v2`; do not silently repurpose a
   deployed request field.
5. Add a test for authorization and one for invalid payload before deploying a
   new write endpoint.

## Deployment status

The OCI service is deployed and reachable at
`https://api.92.4.65.123.sslip.io/health`. It runs as a Docker container bound
only to `127.0.0.1:8001`; Caddy owns public TLS on `443`. OCI's security list
and the VM firewall permit `443`. Full local and OCI deployment instructions are
in [backend/README.md](../backend/README.md).

The FastAPI service is implemented and locally smoke-tested. The Flutter
repository adapters still target the earlier Firebase prototype and must be
switched to `API_BASE_URL` plus secure token storage before the Android app can
use this service in production.
