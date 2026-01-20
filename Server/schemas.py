from datetime import date, time, datetime
from typing import Optional

from pydantic import BaseModel, Field


class VenueCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)


class VenueResponse(BaseModel):
    id: str
    name: str


class EventCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=160)
    facilitator: str = Field(..., min_length=1, max_length=120)
    description: Optional[str] = Field(default=None, max_length=2000)
    venue_name: str = Field(..., min_length=1, max_length=120)
    start_date: date
    start_time: time
    end_date: date
    end_time: time
    override_conflict: bool = False


class EventResponse(BaseModel):
    id: str
    name: str
    facilitator: str
    description: Optional[str] = None
    venue_name: str
    start_date: str
    start_time: str
    end_date: str
    end_time: str
    created_by: str
    created_at: datetime
