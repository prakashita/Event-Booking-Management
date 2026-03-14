"""Idempotency support for critical mutations. Uses Idempotency-Key header and MongoDB storage."""
import json
import re
import uuid
from datetime import datetime

from beanie import Document
from fastapi import Request
from pydantic import Field


# UUID v4 regex for validation
UUID_PATTERN = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[4][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
    re.IGNORECASE,
)

IDEMPOTENCY_TTL_HOURS = 24


class IdempotencyRecord(Document):
    """Stores cached response for an idempotency key. Expired via TTL index."""

    key: str = Field(unique=True)
    status_code: int
    response_body: dict
    created_at: datetime = Field(default_factory=datetime.utcnow)

    class Settings:
        name = "idempotency_keys"
        indexes = [
            # TTL: expire documents 24h after creation
            ({"created_at": 1}, {"expireAfterSeconds": IDEMPOTENCY_TTL_HOURS * 3600}),
        ]


def get_idempotency_key(request: Request) -> str | None:
    """Extract and validate Idempotency-Key header. Returns None if absent or invalid."""
    value = request.headers.get("Idempotency-Key", "").strip()
    if not value:
        return None
    if not UUID_PATTERN.match(value):
        return None
    return value


async def get_cached_response(key: str) -> tuple[int, dict] | None:
    """Return cached (status_code, body) for key, or None."""
    record = await IdempotencyRecord.find_one(IdempotencyRecord.key == key)
    if not record:
        return None
    return record.status_code, record.response_body


async def store_response(key: str, status_code: int, body: dict) -> None:
    """Store response for key. Ignores DuplicateKeyError if another request stored first."""
    from pymongo.errors import DuplicateKeyError
    try:
        await IdempotencyRecord(
            key=key,
            status_code=status_code,
            response_body=body,
        ).insert()
    except DuplicateKeyError:
        pass  # Another request stored first; our mutation already ran, caller returns our response
