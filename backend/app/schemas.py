from datetime import datetime
import re

from pydantic import BaseModel, Field, field_validator

_USERNAME = re.compile(r'^[a-z0-9][a-z0-9._-]{2,31}$')


class Credentials(BaseModel):
    username: str
    password: str = Field(min_length=10, max_length=128)

    @field_validator('username')
    @classmethod
    def validate_username(cls, value: str) -> str:
        username = value.strip().lower()
        if not _USERNAME.fullmatch(username):
            raise ValueError('Username must use 3-32 lowercase letters, numbers, dots, underscores, or hyphens.')
        return username


class TokenRefresh(BaseModel):
    refresh_token: str = Field(min_length=20, max_length=4096)


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = 'bearer'


class UserProfile(BaseModel):
    id: str
    username: str
    role: str


class JourneySelection(BaseModel):
    hub_id: str = Field(min_length=1, max_length=120)
    stop_id: str | None = Field(default=None, max_length=120)
    route_id: str | None = Field(default=None, max_length=120)
    arrival_minutes: int = Field(ge=0, le=1439)
    transfer_minutes: int = Field(ge=0, le=120)
    updated_at: datetime | None = None


class AdvisoryInput(BaseModel):
    station_id: str = Field(min_length=1, max_length=120)
    severity: str = Field(pattern='^(info|minor|major)$')
    message: str = Field(min_length=1, max_length=500)
    expires_at: datetime


class Advisory(BaseModel):
    id: str
    station_id: str
    severity: str
    message: str
    published_at: datetime
    expires_at: datetime


class TransitStationInput(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    status: str = Field(pattern='^(active|closed|limited)$')
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)


class TransitRouteInput(BaseModel):
    short_name: str = Field(min_length=1, max_length=40)
    long_name: str = Field(min_length=1, max_length=240)
    status: str = Field(pattern='^(active|suspended|diverted)$')
    note: str | None = Field(default=None, max_length=500)
    geometry: list['MapPoint'] | None = Field(default=None, max_length=200)


class MapPoint(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class TransitReferenceItem(BaseModel):
    id: str
    entity_type: str
    operator: str
    payload: dict
    updated_at: datetime


class TicketLegInput(BaseModel):
    mode: str = Field(pattern='^(Walk|Metro|AMTS|BRTS)$')
    route_name: str | None = Field(default=None, max_length=120)
    from_name: str = Field(min_length=1, max_length=160)
    to_name: str = Field(min_length=1, max_length=160)
    minutes: int = Field(ge=0, le=360)


class TicketOrderInput(BaseModel):
    rider_name: str = Field(min_length=2, max_length=100)
    travel_for_self: bool
    origin_name: str = Field(min_length=1, max_length=160)
    destination_name: str = Field(min_length=1, max_length=160)
    itinerary: list[TicketLegInput] = Field(min_length=1, max_length=30)
    fare_amount: int = Field(ge=0, le=10000)

    @field_validator('rider_name')
    @classmethod
    def normalize_rider_name(cls, value: str) -> str:
        return ' '.join(value.split())


class TicketOrder(BaseModel):
    id: str
    rider_name: str
    travel_for_self: bool
    origin_name: str
    destination_name: str
    itinerary: list[TicketLegInput]
    fare_amount: int
    status: str
    created_at: datetime
