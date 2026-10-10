import os

import firebase_admin
from firebase_admin import auth
from firebase_functions import https_fn
from flask import jsonify
import jwt
from jwt import PyJWKClient

firebase_admin.initialize_app()


def _configuration(name: str) -> str:
    value = os.environ.get(name, '')
    if not value:
        raise ValueError(f'Missing required server configuration: {name}')
    return value


@https_fn.on_request(region='asia-south1')
def exchange_external_jwt(request: https_fn.Request) -> https_fn.Response:
    if request.method != 'POST':
        return jsonify(error='Use POST.'), 405

    payload = request.get_json(silent=True) or {}
    external_jwt = payload.get('externalJwt')
    if not isinstance(external_jwt, str) or not external_jwt:
        return jsonify(error='externalJwt is required.'), 400

    try:
        jwks_client = PyJWKClient(_configuration('EXTERNAL_JWT_JWKS_URL'))
        signing_key = jwks_client.get_signing_key_from_jwt(external_jwt)
        claims = jwt.decode(
            external_jwt,
            signing_key.key,
            algorithms=['RS256'],
            audience=_configuration('EXTERNAL_JWT_AUDIENCE'),
            issuer=_configuration('EXTERNAL_JWT_ISSUER'),
            options={'require': ['exp', 'iat', 'sub']},
        )
        uid = claims['sub']
        if not isinstance(uid, str) or not uid:
            return jsonify(error='JWT subject is invalid.'), 401
        additional_claims = {
            key: claims[key]
            for key in ('username', 'role')
            if isinstance(claims.get(key), str)
        }
        custom_token = auth.create_custom_token(uid, additional_claims).decode('utf-8')
        return jsonify(customToken=custom_token)
    except (jwt.PyJWTError, ValueError) as error:
        return jsonify(error=f'Token exchange denied: {error}'), 401
