"""Per-event group chat: created when registrar approves; facility/marketing/IT join when they accept."""

import logging
from datetime import datetime, timezone
from typing import Optional

from models import ChatConversation

logger = logging.getLogger("event-booking.event_chat")


async def get_event_thread(event_id: str) -> Optional[ChatConversation]:
    if not event_id:
        return None
    return await ChatConversation.find_one(ChatConversation.event_id == event_id)


async def ensure_event_group_chat(
    event_id: str,
    event_name: str,
    creator_user_id: str,
    registrar_user_id: str,
) -> Optional[ChatConversation]:
    """Create event group chat with creator + registrar, or return existing."""
    if not event_id or not creator_user_id or not registrar_user_id:
        logger.warning("ensure_event_group_chat: missing ids")
        return None
    existing = await get_event_thread(event_id)
    if existing:
        merged = sorted(set(existing.participants + [creator_user_id, registrar_user_id]))
        if merged != existing.participants:
            existing.participants = merged
            existing.updated_at = datetime.now(timezone.utc)
            if event_name and not existing.title:
                existing.title = event_name[:200]
            await existing.save()
        return existing

    participants = sorted({creator_user_id, registrar_user_id})
    conv = ChatConversation(
        participants=list(participants),
        thread_kind="event",
        event_id=event_id,
        title=(event_name or "Event")[:200],
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    await conv.insert()
    return conv


async def add_participant_to_event_chat(event_id: str, user_id: str) -> None:
    """Add facility / marketing / IT user when they accept a request for this event."""
    if not event_id or not user_id:
        return
    conv = await get_event_thread(event_id)
    if not conv:
        logger.warning("add_participant_to_event_chat: no thread for event %s", event_id)
        return
    if user_id in conv.participants:
        return
    conv.participants = list(conv.participants) + [user_id]
    conv.updated_at = datetime.now(timezone.utc)
    await conv.save()
