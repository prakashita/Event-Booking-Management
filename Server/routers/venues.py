from fastapi import APIRouter, Depends, HTTPException, status

from models import Venue, User
from routers.deps import get_current_user
from schemas import VenueCreate, VenueResponse

router = APIRouter(prefix="/venues", tags=["Venues"])
DEFAULT_VENUES = [
    "Auditorium Hall",
    "Innovation Lab",
    "Conference Center",
    "Seminar Room B",
    "Open Air Courtyard",
]


@router.get("", response_model=list[VenueResponse])
async def list_venues():
    venues = await Venue.find_all().sort("name").to_list()
    return [VenueResponse(id=str(venue.id), name=venue.name) for venue in venues]


@router.post("", response_model=VenueResponse, status_code=status.HTTP_201_CREATED)
async def create_venue(payload: VenueCreate, user: User = Depends(get_current_user)):
    existing = await Venue.find_one(Venue.name == payload.name)
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Venue already exists",
        )

    venue = Venue(name=payload.name)
    await venue.insert()
    return VenueResponse(id=str(venue.id), name=venue.name)


@router.post("/seed")
async def seed_venues(user: User = Depends(get_current_user)):
    inserted = 0
    for name in DEFAULT_VENUES:
        existing = await Venue.find_one(Venue.name == name)
        if existing:
            continue
        await Venue(name=name).insert()
        inserted += 1

    return {"inserted": inserted, "total": len(DEFAULT_VENUES)}
