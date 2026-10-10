import sqlite3
from pathlib import Path

from app.config import Settings


def connect(settings: Settings) -> sqlite3.Connection:
    database_path = Path(settings.database_path)
    database_path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(database_path, check_same_thread=False)
    connection.row_factory = sqlite3.Row
    connection.execute('PRAGMA foreign_keys = ON')
    return connection


def initialize(settings: Settings) -> None:
    with connect(settings) as connection:
        connection.executescript(
            '''
            CREATE TABLE IF NOT EXISTS users (
              id TEXT PRIMARY KEY,
              username TEXT UNIQUE NOT NULL,
              password_hash TEXT NOT NULL,
              role TEXT NOT NULL DEFAULT 'passenger',
              created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS refresh_tokens (
              id TEXT PRIMARY KEY,
              user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
              token_hash TEXT NOT NULL,
              expires_at TEXT NOT NULL,
              revoked_at TEXT
            );
            CREATE TABLE IF NOT EXISTS journey_selections (
              user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
              hub_id TEXT NOT NULL,
              stop_id TEXT,
              route_id TEXT,
              arrival_minutes INTEGER NOT NULL,
              transfer_minutes INTEGER NOT NULL,
              updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS service_advisories (
              id TEXT PRIMARY KEY,
              station_id TEXT NOT NULL,
              severity TEXT NOT NULL,
              message TEXT NOT NULL,
              published_by TEXT NOT NULL REFERENCES users(id),
              published_at TEXT NOT NULL,
              expires_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS service_advisories_active
              ON service_advisories (expires_at, station_id);
            CREATE TABLE IF NOT EXISTS transit_reference (
              id TEXT PRIMARY KEY,
              entity_type TEXT NOT NULL CHECK(entity_type IN ('station', 'route')),
              operator TEXT NOT NULL CHECK(operator IN ('Metro', 'AMTS', 'BRTS')),
              payload_json TEXT NOT NULL,
              updated_by TEXT NOT NULL REFERENCES users(id),
              updated_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS transit_reference_type
              ON transit_reference (entity_type, operator, updated_at);
            CREATE TABLE IF NOT EXISTS ticket_orders (
              id TEXT PRIMARY KEY,
              buyer_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
              rider_name TEXT NOT NULL,
              travel_for_self INTEGER NOT NULL CHECK(travel_for_self IN (0, 1)),
              origin_name TEXT NOT NULL,
              destination_name TEXT NOT NULL,
              itinerary_json TEXT NOT NULL,
              fare_amount INTEGER NOT NULL CHECK(fare_amount >= 0),
              status TEXT NOT NULL CHECK(status IN ('issued_demo', 'cancelled')),
              created_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS ticket_orders_buyer_created
              ON ticket_orders (buyer_id, created_at DESC);
            '''
        )
