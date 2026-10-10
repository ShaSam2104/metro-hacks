# MetroLink FastAPI Backend

This is the trusted, self-hosted backend for the MetroLink Android app. It is
independent of the Firebase project, which means Firebase billing or Identity
Platform configuration is not needed for account login and data synchronization.

## Responsibilities

| Route | Authentication | Responsibility |
| --- | --- | --- |
| `GET /health` | None | Readiness check for the reverse proxy and deploys. |
| `GET /v1/places/search?q=...` | None | Ahmedabad-bounded OpenStreetMap place lookup with in-process caching. |
| `POST /v1/auth/register` | None | Create an Argon2-protected account and return token pair. |
| `POST /v1/auth/login` | None | Verify credentials and return token pair. |
| `POST /v1/auth/refresh` | Refresh token | Rotate a refresh token. |
| `GET /v1/me` | Access token | Return the caller's username and server-side role. |
| `GET`, `PUT /v1/journey-selection` | Access token | Read or synchronize the caller's current choice. |
| `GET`, `POST /v1/ticket-orders` | Access token | List the caller's ticket wallet or issue a demo journey pass for the purchaser or a named rider. |
| `GET /v1/service-advisories` | None | Read current public advisories. |
| `POST /v1/service-advisories` | Operator access token | Publish an advisory. |
| `GET /v1/transit/reference` | None | Read the published station and route reference overlay. |
| `PUT /v1/transit/stations/{id}` | Operator access token | Create or update a Metro station record. |
| `PUT /v1/transit/routes/{operator}/{id}` | Operator access token | Create or update an AMTS or BRTS route record, optionally with a coordinate geometry. |
| `DELETE /v1/transit/reference/{id}` | Operator access token | Remove a published reference record. |

Access tokens last one hour. Refresh tokens are stored only as SHA-256
fingerprints in SQLite and rotate on use. Passwords use Argon2 through `pwdlib`.
The API never returns password hashes, refresh-token fingerprints, or another
user's journey selection or ticket orders. Ticket orders currently use the
`issued_demo` status: they are account-owned journey passes with an immutable
route/fare snapshot, not a real payment settlement or operator ticket API.

## Local run

```sh
cd backend
cp .env.example .env
# Replace the example secret before continuing.
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
set -a; source .env; set +a
export METROLINK_DATABASE_PATH="$PWD/.local/metrolink.db"
uvicorn app.main:app --reload
```

Open `http://127.0.0.1:8000/docs` for the generated OpenAPI interface.

## Operator setup

Create the staff account through the normal registration route, then perform
the one-time role assignment from a shell on the VM:

```sh
docker compose exec api python -m app.admin promote-operator staff_username
```

This is intentionally not an HTTP endpoint. A passenger cannot promote itself,
and the service checks the stored role on every administrative request.

For the hackathon demo environment, the seeded operator account is:

```text
username: operator.demo
password: MetroLink!2026
```

Change or remove this account before sharing the deployment beyond the event.

Station records accept decimal `latitude` and `longitude`. Route records may
include up to 200 ordered `{ "latitude": number, "longitude": number }`
points in `geometry`; the operator map renders that path after it is saved.

## OCI deployment

The container only binds port 8000 to loopback. Put Caddy or Nginx in front of
it for TLS and public routing; never expose the FastAPI development server
directly to the internet.

```sh
ssh -i /Users/shasam/Dev/SSH_KEYS/ssh-key-2026-02-06.key ubuntu@92.4.65.123
sudo mkdir -p /opt/metrolink
sudo chown ubuntu:ubuntu /opt/metrolink
```

Copy this `backend/` directory to `/opt/metrolink`, create `/opt/metrolink/.env`
from `.env.example` with a newly generated secret, then:

```sh
cd /opt/metrolink
docker compose up --build -d
curl http://127.0.0.1:8001/health
```

The deployed hackathon endpoint is temporarily available at
`https://api.92.4.65.123.sslip.io`. Caddy terminates TLS on port `443` and
proxies privately to the container on `127.0.0.1:8001`. Build Android with:

```sh
flutter build apk --debug \
  --dart-define=API_BASE_URL=https://api.92.4.65.123.sslip.io
```

Replace the temporary `sslip.io` hostname with a project-owned domain before a
long-lived release. Do not expose port `8001` publicly.
