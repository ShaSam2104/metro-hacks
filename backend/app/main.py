from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
import sqlite3
import uuid
import json
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from fastapi import Depends, FastAPI, HTTPException, Response, status
from fastapi.middleware.cors import CORSMiddleware
import jwt

from app.config import Settings, get_settings
from app.database import connect, initialize
from app.dependencies import current_user_id, database, operator_user_id, settings
from app.schemas import Advisory, AdvisoryInput, Credentials, JourneySelection, TicketOrder, TicketOrderInput, TokenPair, TokenRefresh, TransitReferenceItem, TransitRouteInput, TransitStationInput, UserProfile
from app.security import decode_token, hash_password, issue_token, new_refresh_id, token_fingerprint, verify_password


def _token_pair(settings_value: Settings, connection: sqlite3.Connection, user_id: str) -> TokenPair:
    access = issue_token(settings_value, user_id, 'access', timedelta(minutes=settings_value.access_token_minutes))
    refresh = issue_token(settings_value, user_id, 'refresh', timedelta(days=settings_value.refresh_token_days))
    refresh_claims = decode_token(settings_value, refresh, 'refresh')
    connection.execute(
        'INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at) VALUES (?, ?, ?, ?)',
        (refresh_claims['jti'], user_id, token_fingerprint(refresh), datetime.fromtimestamp(refresh_claims['exp'], timezone.utc).isoformat()),
    )
    connection.commit()
    return TokenPair(access_token=access, refresh_token=refresh)


@asynccontextmanager
async def lifespan(_: FastAPI):
    initialize(get_settings())
    yield


app = FastAPI(title='MetroLink API', version='0.1.0', lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=list(get_settings().cors_origins),
    allow_credentials=False,
    allow_methods=['GET', 'POST', 'PUT', 'DELETE'],
    allow_headers=['Authorization', 'Content-Type'],
)

_place_search_cache: dict[str, list[dict]] = {}


@app.get('/health')
def health():
    return {'service': 'metrolink-api', 'status': 'ok'}


@app.get('/v1/places/search')
def search_places(q: str, limit: int = 5):
    """Resolve a passenger-entered Ahmedabad place through Nominatim.

    The client only calls this endpoint on submit. Results are bounded to the
    Ahmedabad area and cached in-process; the Flutter app falls back to its
    bundled landmarks and transit stops when this lookup is unavailable.
    """
    query = q.strip()
    if len(query) < 2:
        return []
    cache_key = query.lower()
    if cache_key in _place_search_cache:
        return _place_search_cache[cache_key]
    parameters = urlencode({
        'q': f'{query}, Ahmedabad, Gujarat, India',
        'format': 'jsonv2',
        'limit': min(max(limit, 1), 8),
        'bounded': '1',
        # left, top, right, bottom: Ahmedabad and immediate urban area.
        'viewbox': '72.42,23.18,72.72,22.86',
    })
    request = Request(
        f'https://nominatim.openstreetmap.org/search?{parameters}',
        headers={'User-Agent': 'MetroLink-Metro-Hacks/1.0'},
    )
    try:
        with urlopen(request, timeout=4) as response:
            raw = json.loads(response.read().decode('utf-8'))
        results = [
            {
                'name': item['display_name'],
                'latitude': float(item['lat']),
                'longitude': float(item['lon']),
            }
            for item in raw
            if item.get('display_name') and item.get('lat') and item.get('lon')
        ]
    except Exception:
        return []
    _place_search_cache[cache_key] = results
    return results


@app.post('/v1/auth/register', response_model=TokenPair, status_code=status.HTTP_201_CREATED)
def register(credentials: Credentials, database_connection: sqlite3.Connection = Depends(database), settings_value: Settings = Depends(settings)):
    user_id = str(uuid.uuid4())
    try:
        database_connection.execute(
            'INSERT INTO users (id, username, password_hash, created_at) VALUES (?, ?, ?, ?)',
            (user_id, credentials.username, hash_password(credentials.password), datetime.now(timezone.utc).isoformat()),
        )
        database_connection.commit()
    except sqlite3.IntegrityError as error:
        raise HTTPException(status_code=409, detail='Username is already in use.') from error
    return _token_pair(settings_value, database_connection, user_id)


@app.post('/v1/auth/login', response_model=TokenPair)
def login(credentials: Credentials, database_connection: sqlite3.Connection = Depends(database), settings_value: Settings = Depends(settings)):
    row = database_connection.execute(
        'SELECT id, password_hash FROM users WHERE username = ?', (credentials.username,)
    ).fetchone()
    if row is None or not verify_password(credentials.password, row['password_hash']):
        raise HTTPException(status_code=401, detail='Invalid username or password.')
    return _token_pair(settings_value, database_connection, row['id'])


@app.post('/v1/auth/refresh', response_model=TokenPair)
def refresh(token_input: TokenRefresh, database_connection: sqlite3.Connection = Depends(database), settings_value: Settings = Depends(settings)):
    try:
        claims = decode_token(settings_value, token_input.refresh_token, 'refresh')
    except jwt.PyJWTError as error:
        raise HTTPException(status_code=401, detail='Invalid refresh token.') from error
    row = database_connection.execute(
        'SELECT id FROM refresh_tokens WHERE id = ? AND user_id = ? AND token_hash = ? AND revoked_at IS NULL AND expires_at > ?',
        (claims['jti'], claims['sub'], token_fingerprint(token_input.refresh_token), datetime.now(timezone.utc).isoformat()),
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=401, detail='Invalid refresh token.')
    database_connection.execute('UPDATE refresh_tokens SET revoked_at = ? WHERE id = ?', (datetime.now(timezone.utc).isoformat(), claims['jti']))
    database_connection.commit()
    return _token_pair(settings_value, database_connection, claims['sub'])


@app.get('/v1/me', response_model=UserProfile)
def me(user_id: str = Depends(current_user_id), database_connection: sqlite3.Connection = Depends(database)):
    row = database_connection.execute('SELECT id, username, role FROM users WHERE id = ?', (user_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=401, detail='Account no longer exists.')
    return dict(row)


@app.get('/v1/journey-selection', response_model=JourneySelection | None)
def get_journey_selection(user_id: str = Depends(current_user_id), database_connection: sqlite3.Connection = Depends(database)):
    row = database_connection.execute('SELECT * FROM journey_selections WHERE user_id = ?', (user_id,)).fetchone()
    return dict(row) if row else None


@app.put('/v1/journey-selection', response_model=JourneySelection)
def put_journey_selection(selection: JourneySelection, user_id: str = Depends(current_user_id), database_connection: sqlite3.Connection = Depends(database)):
    updated_at = datetime.now(timezone.utc).isoformat()
    database_connection.execute(
        '''INSERT INTO journey_selections (user_id, hub_id, stop_id, route_id, arrival_minutes, transfer_minutes, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(user_id) DO UPDATE SET hub_id=excluded.hub_id, stop_id=excluded.stop_id, route_id=excluded.route_id,
           arrival_minutes=excluded.arrival_minutes, transfer_minutes=excluded.transfer_minutes, updated_at=excluded.updated_at''',
        (user_id, selection.hub_id, selection.stop_id, selection.route_id, selection.arrival_minutes, selection.transfer_minutes, updated_at),
    )
    database_connection.commit()
    return selection.model_copy(update={'updated_at': updated_at})


def _ticket_order_from_row(row: sqlite3.Row) -> dict:
    return {
        'id': row['id'],
        'rider_name': row['rider_name'],
        'travel_for_self': bool(row['travel_for_self']),
        'origin_name': row['origin_name'],
        'destination_name': row['destination_name'],
        'itinerary': json.loads(row['itinerary_json']),
        'fare_amount': row['fare_amount'],
        'status': row['status'],
        'created_at': row['created_at'],
    }


@app.get('/v1/ticket-orders', response_model=list[TicketOrder])
def list_ticket_orders(user_id: str = Depends(current_user_id), database_connection: sqlite3.Connection = Depends(database)):
    rows = database_connection.execute(
        'SELECT * FROM ticket_orders WHERE buyer_id = ? ORDER BY created_at DESC',
        (user_id,),
    ).fetchall()
    return [_ticket_order_from_row(row) for row in rows]


@app.post('/v1/ticket-orders', response_model=TicketOrder, status_code=status.HTTP_201_CREATED)
def create_ticket_order(order: TicketOrderInput, user_id: str = Depends(current_user_id), database_connection: sqlite3.Connection = Depends(database)):
    order_id = str(uuid.uuid4())
    created_at = datetime.now(timezone.utc).isoformat()
    database_connection.execute(
        '''INSERT INTO ticket_orders
           (id, buyer_id, rider_name, travel_for_self, origin_name, destination_name, itinerary_json, fare_amount, status, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        (
            order_id,
            user_id,
            order.rider_name,
            int(order.travel_for_self),
            order.origin_name,
            order.destination_name,
            json.dumps([leg.model_dump() for leg in order.itinerary]),
            order.fare_amount,
            'issued_demo',
            created_at,
        ),
    )
    database_connection.commit()
    row = database_connection.execute('SELECT * FROM ticket_orders WHERE id = ?', (order_id,)).fetchone()
    return _ticket_order_from_row(row)


@app.get('/v1/service-advisories', response_model=list[Advisory])
def list_advisories(station_id: str | None = None, database_connection: sqlite3.Connection = Depends(database)):
    query = 'SELECT id, station_id, severity, message, published_at, expires_at FROM service_advisories WHERE expires_at > ?'
    parameters: list[str] = [datetime.now(timezone.utc).isoformat()]
    if station_id:
        query += ' AND station_id = ?'
        parameters.append(station_id)
    query += ' ORDER BY published_at DESC'
    return [dict(row) for row in database_connection.execute(query, parameters).fetchall()]


@app.get('/v1/transit/reference', response_model=list[TransitReferenceItem])
def transit_reference(database_connection: sqlite3.Connection = Depends(database)):
    rows = database_connection.execute(
        'SELECT id, entity_type, operator, payload_json, updated_at FROM transit_reference ORDER BY updated_at DESC'
    ).fetchall()
    return [
        {
            'id': row['id'],
            'entity_type': row['entity_type'],
            'operator': row['operator'],
            'payload': json.loads(row['payload_json']),
            'updated_at': row['updated_at'],
        }
        for row in rows
    ]


def _upsert_transit_reference(entity_id: str, entity_type: str, operator: str, payload: dict, user_id: str, database_connection: sqlite3.Connection) -> dict:
    updated_at = datetime.now(timezone.utc).isoformat()
    database_connection.execute(
        '''INSERT INTO transit_reference (id, entity_type, operator, payload_json, updated_by, updated_at)
           VALUES (?, ?, ?, ?, ?, ?)
           ON CONFLICT(id) DO UPDATE SET operator=excluded.operator, payload_json=excluded.payload_json,
           updated_by=excluded.updated_by, updated_at=excluded.updated_at''',
        (entity_id, entity_type, operator, json.dumps(payload), user_id, updated_at),
    )
    database_connection.commit()
    return {'id': entity_id, 'entity_type': entity_type, 'operator': operator, 'payload': payload, 'updated_at': updated_at}


@app.put('/v1/transit/stations/{station_id}', response_model=TransitReferenceItem)
def upsert_station(station_id: str, station: TransitStationInput, user_id: str = Depends(operator_user_id), database_connection: sqlite3.Connection = Depends(database)):
    return _upsert_transit_reference(station_id, 'station', 'Metro', station.model_dump(exclude_none=True), user_id, database_connection)


@app.put('/v1/transit/routes/{operator}/{route_id}', response_model=TransitReferenceItem)
def upsert_route(operator: str, route_id: str, route: TransitRouteInput, user_id: str = Depends(operator_user_id), database_connection: sqlite3.Connection = Depends(database)):
    normalized_operator = operator.upper()
    if normalized_operator not in {'AMTS', 'BRTS'}:
        raise HTTPException(status_code=400, detail='Route operator must be AMTS or BRTS.')
    payload = route.model_dump(exclude_none=True) | {'source_id': route_id}
    return _upsert_transit_reference(f'route:{normalized_operator}:{route_id}', 'route', normalized_operator, payload, user_id, database_connection)


@app.delete('/v1/transit/reference/{reference_id}', status_code=status.HTTP_204_NO_CONTENT)
def delete_transit_reference(reference_id: str, _: str = Depends(operator_user_id), database_connection: sqlite3.Connection = Depends(database)) -> Response:
    result = database_connection.execute('DELETE FROM transit_reference WHERE id = ?', (reference_id,))
    database_connection.commit()
    if result.rowcount != 1:
        raise HTTPException(status_code=404, detail='Transit reference was not found.')
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.post('/v1/service-advisories', response_model=Advisory, status_code=status.HTTP_201_CREATED)
def publish_advisory(advisory: AdvisoryInput, user_id: str = Depends(operator_user_id), database_connection: sqlite3.Connection = Depends(database)):
    if advisory.expires_at <= datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail='Advisory expiry must be in the future.')
    advisory_id = str(uuid.uuid4())
    published_at = datetime.now(timezone.utc)
    database_connection.execute(
        'INSERT INTO service_advisories (id, station_id, severity, message, published_by, published_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        (advisory_id, advisory.station_id.strip(), advisory.severity, advisory.message.strip(), user_id, published_at.isoformat(), advisory.expires_at.isoformat()),
    )
    database_connection.commit()
    return Advisory(id=advisory_id, station_id=advisory.station_id.strip(), severity=advisory.severity, message=advisory.message.strip(), published_at=published_at, expires_at=advisory.expires_at)
