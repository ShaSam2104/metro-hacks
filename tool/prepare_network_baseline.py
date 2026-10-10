#!/usr/bin/env python3
"""Build the map baseline from the supplied Metro Hacks transit snapshot."""

import argparse
import csv
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    arguments = parser.parse_args()

    stops = []
    with arguments.source.open(newline='', encoding='utf-8') as source:
        for row in csv.DictReader(source):
            try:
                latitude = float(row['lat'])
                longitude = float(row['lon'])
            except (KeyError, TypeError, ValueError):
                continue
            agency = row['agency'].strip().lower()
            if agency not in {'metro', 'municipal_bus', 'brt'}:
                continue
            stops.append({
                'id': row['stop_id'],
                'name': row['name'],
                'operator': {
                    'metro': 'Metro',
                    'municipal_bus': 'AMTS',
                    'brt': 'BRTS',
                }[agency],
                'latitude': latitude,
                'longitude': longitude,
            })

    counts = Counter(stop['operator'] for stop in stops)
    output = {
        'metadata': {
            'source': 'Metro Hacks supplied secondary_scraped/stops.csv',
            'generated_at': datetime.now(timezone.utc).isoformat(),
            'counts': dict(counts),
        },
        'stops': stops,
    }
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(output, separators=(',', ':')), encoding='utf-8')
    print(f'Wrote {len(stops)} mapped stops: {dict(counts)}')


if __name__ == '__main__':
    main()
