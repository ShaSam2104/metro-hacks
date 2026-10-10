from datetime import datetime, timedelta, timezone
import hashlib
import secrets
import uuid

import jwt
from pwdlib import PasswordHash

from app.config import Settings

_password_hash = PasswordHash.recommended()


def hash_password(password: str) -> str:
    return _password_hash.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    return _password_hash.verify(password, password_hash)


def issue_token(settings: Settings, user_id: str, token_type: str, lifetime: timedelta) -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode(
        {
            'sub': user_id,
            'type': token_type,
            'iss': settings.jwt_issuer,
            'iat': now,
            'exp': now + lifetime,
            'jti': str(uuid.uuid4()),
        },
        settings.jwt_secret,
        algorithm='HS256',
    )


def decode_token(settings: Settings, token: str, token_type: str) -> dict:
    claims = jwt.decode(
        token,
        settings.jwt_secret,
        algorithms=['HS256'],
        issuer=settings.jwt_issuer,
        options={'require': ['sub', 'exp', 'iat', 'jti']},
    )
    if claims.get('type') != token_type:
        raise jwt.InvalidTokenError('Incorrect token type.')
    return claims


def token_fingerprint(token: str) -> str:
    return hashlib.sha256(token.encode('utf-8')).hexdigest()


def new_refresh_id() -> str:
    return secrets.token_urlsafe(24)
