#!/usr/bin/env python3
"""Create a compact offline AMTS+BRTS+Metro routing graph from supplied GTFS."""

import argparse
import csv
import json
import math
from datetime import datetime, timezone
from pathlib import Path


BLUE_LINE = [
    ('Vastral Gam', 22.99723908320867, 72.66747041572408),
    ('Nirant Cross Road', 22.999863263480865, 72.65888489671117),
    ('Vastral', 23.003594691685002, 72.6476768142666),
    ('Rabari Colony', 23.005542671311495, 72.63549394881706),
    ('Amraiwadi', 23.007763993796566, 72.62878346307075),
    ('Apparel Park', 23.010719725226565, 72.61816883538819),
    ('Kankaria East', 23.014773992937037, 72.60693552603419),
    ('Kalupur Metro Station', 23.02477887132399, 72.6029083880447),
    ('Gheekanta', 23.02859425164894, 72.58683730138765),
    ('Shahpur', 23.039191985120183, 72.5812443430793),
    ('Old High Court', 23.03744440876014, 72.56701000166855),
    ('Stadium', 23.03984049870335, 72.56180665079206),
    ('Commerce Six Road', 23.040721303939534, 72.55302496018233),
    ('Gujarat University', 23.04486062790798, 72.5436240789925),
    ('Gurukul Road', 23.04593980470685, 72.53509879782438),
    ('Doordarshan Kendra', 23.048217078771085, 72.5247565213341),
    ('Thaltej Gam', 23.049821545405166, 72.51608014554085),
]

PLACES = [
    ('thaltej-gam', 'Thaltej Gam Metro', 23.049821545405166, 72.51608014554085),
    ('gujarat-university', 'Gujarat University', 23.04486062790798, 72.5436240789925),
    ('old-high-court-district', 'Old High Court district', 23.03744440876014, 72.56701000166855),
    ('kalupur-railway-station', 'Kalupur Railway Station', 23.02477887132399, 72.6029083880447),
    ('kankaria-east', 'Kankaria East', 23.014773992937037, 72.60693552603419),
    ('vastral-gam', 'Vastral Gam Metro', 22.99723908320867, 72.66747041572408),
    ('maninagar', 'Maninagar', 22.997728, 72.611414),
    ('bopal-gam', 'Bopal Gam', 23.03407, 72.464154),
    ('ghuma-gam', 'Ghuma Gam', 23.031022, 72.448416),
    ('science-city', 'Science City', 23.080317, 72.499527),
]


def clock_minutes(value: str) -> int | None:
    try:
        hour, minute, second = map(int, value.split(':'))
        return hour * 60 + minute + round(second / 60)
    except ValueError:
        return None


def haversine_meters(first: dict, second: dict) -> float:
    latitude = math.radians(second['latitude'] - first['latitude'])
    longitude = math.radians(second['longitude'] - first['longitude'])
    a = math.sin(latitude / 2) ** 2 + math.cos(math.radians(first['latitude'])) * math.cos(math.radians(second['latitude'])) * math.sin(longitude / 2) ** 2
    return 6371000 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--gtfs', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    arguments = parser.parse_args()
    gtfs = arguments.gtfs

    routes = {}
    with (gtfs / 'routes.txt').open(newline='', encoding='utf-8') as source:
        for row in csv.DictReader(source):
            if row['agency_id'] not in {'AMTS', 'AJL'}:
                continue
            routes[row['route_id']] = {
                'operator': 'BRTS' if row['agency_id'] == 'AJL' else 'AMTS',
                'shortName': row['route_short_name'] or row['route_id'],
                'longName': row['route_long_name'],
            }

    trip_routes = {}
    with (gtfs / 'trips.txt').open(newline='', encoding='utf-8') as source:
        for row in csv.DictReader(source):
            if row['route_id'] in routes:
                trip_routes[row['trip_id']] = row['route_id']

    all_stops = {}
    with (gtfs / 'stops.txt').open(newline='', encoding='utf-8') as source:
        for row in csv.DictReader(source):
            try:
                all_stops[row['stop_id']] = {
                    'id': row['stop_id'],
                    'name': row['stop_name'],
                    'latitude': float(row['stop_lat']),
                    'longitude': float(row['stop_lon']),
                }
            except ValueError:
                continue

    edges = {}
    active_stops = set()
    previous_trip = None
    previous = None
    with (gtfs / 'stop_times.txt').open(newline='', encoding='utf-8') as source:
        for row in csv.DictReader(source):
            trip_id = row['trip_id']
            route_id = trip_routes.get(trip_id)
            if route_id is None:
                continue
            if trip_id != previous_trip:
                previous_trip = trip_id
                previous = None
            stop_id = row['stop_id']
            if stop_id not in all_stops:
                previous = None
                continue
            active_stops.add(stop_id)
            current = (stop_id, clock_minutes(row['arrival_time']))
            if previous is not None and previous[0] != current[0]:
                elapsed = (current[1] - previous[1]) if current[1] is not None and previous[1] is not None else 3
                minutes = max(1, min(elapsed, 20))
                key = (previous[0], current[0], route_id)
                edges[key] = min(edges.get(key, minutes), minutes)
            previous = current

    nodes = {stop_id: all_stops[stop_id] | {'operator': 'AMTS/BRTS'} for stop_id in active_stops}
    for index, (name, latitude, longitude) in enumerate(BLUE_LINE):
        identifier = f'metro-blue-{index}'
        nodes[identifier] = {
            'id': identifier,
            'name': name,
            'latitude': latitude,
            'longitude': longitude,
            'operator': 'Metro',
        }
    output_edges = [
        {'from': first, 'to': second, 'routeId': route_id, 'mode': routes[route_id]['operator'], 'minutes': minutes}
        for (first, second, route_id), minutes in edges.items()
    ]
    for index in range(len(BLUE_LINE) - 1):
        for first, second in ((f'metro-blue-{index}', f'metro-blue-{index + 1}'), (f'metro-blue-{index + 1}', f'metro-blue-{index}')):
            output_edges.append({'from': first, 'to': second, 'routeId': 'metro-blue-line', 'mode': 'Metro', 'minutes': 3})
    output = {
        'metadata': {
            'source': 'Metro Hacks supplied GTFS secondary snapshot, 2026-09-30',
            'generatedAt': datetime.now(timezone.utc).isoformat(),
            'note': 'AMTS/BRTS travel times use the fastest observed scheduled link time; Metro Blue Line uses the published end-to-end runtime distributed across stations.',
        },
        'places': [{'id': identifier, 'name': name, 'latitude': latitude, 'longitude': longitude} for identifier, name, latitude, longitude in PLACES],
        'nodes': list(nodes.values()),
        'routes': routes,
        'edges': output_edges,
    }
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(output, separators=(',', ':')), encoding='utf-8')
    print(f'Wrote {len(nodes)} nodes, {len(output_edges)} directed ride edges, {len(routes)} routes.')


if __name__ == '__main__':
    main()
