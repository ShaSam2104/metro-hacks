from dataclasses import dataclass
import os


@dataclass(frozen=True)
class Settings:
    jwt_secret: str
    jwt_issuer: str = 'metrolink-api'
    access_token_minutes: int = 60
    refresh_token_days: int = 14
    database_path: str = '/data/metrolink.db'
    cors_origins: tuple[str, ...] = ()


def get_settings() -> Settings:
    secret = os.getenv('METROLINK_JWT_SECRET', '')
    if len(secret) < 32:
        raise RuntimeError('METROLINK_JWT_SECRET must be at least 32 characters.')
    return Settings(
        jwt_secret=secret,
        database_path=os.getenv('METROLINK_DATABASE_PATH', '/data/metrolink.db'),
        cors_origins=tuple(
            origin.strip()
            for origin in os.getenv('METROLINK_CORS_ORIGINS', '').split(',')
            if origin.strip()
        ),
    )
