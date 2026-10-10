import sqlite3

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
import jwt

from app.config import Settings, get_settings
from app.database import connect
from app.security import decode_token

_bearer = HTTPBearer(auto_error=False)


def settings() -> Settings:
    return get_settings()


def database(settings_value: Settings = Depends(settings)):
    connection = connect(settings_value)
    try:
        yield connection
    finally:
        connection.close()


def current_user_id(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    settings_value: Settings = Depends(settings),
) -> str:
    if credentials is None:
        raise HTTPException(status_code=401, detail='Authentication is required.')
    try:
        return decode_token(settings_value, credentials.credentials, 'access')['sub']
    except jwt.PyJWTError as error:
        raise HTTPException(status_code=401, detail='Invalid access token.') from error


def operator_user_id(
    user_id: str = Depends(current_user_id),
    database_connection: sqlite3.Connection = Depends(database),
) -> str:
    row = database_connection.execute(
        'SELECT 1 FROM users WHERE id = ? AND role = ?', (user_id, 'operator')
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=403, detail='Operator authorization is required.')
    return user_id
