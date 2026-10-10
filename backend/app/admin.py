"""Deliberate, server-side-only administrative commands."""

import argparse

from app.config import get_settings
from app.database import connect, initialize


def main() -> None:
    parser = argparse.ArgumentParser(description='MetroLink backend administration')
    subcommands = parser.add_subparsers(dest='command', required=True)
    promote = subcommands.add_parser('promote-operator')
    promote.add_argument('username')
    arguments = parser.parse_args()

    settings = get_settings()
    initialize(settings)
    with connect(settings) as connection:
        result = connection.execute(
            'UPDATE users SET role = ? WHERE username = ?',
            ('operator', arguments.username.strip().lower()),
        )
        connection.commit()
    if result.rowcount != 1:
        raise SystemExit('No user with that username exists.')
    print('Operator role assigned.')


if __name__ == '__main__':
    main()
