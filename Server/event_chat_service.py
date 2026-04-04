"""Per-event group chat: created when registrar approves; facility/marketing/IT join when they accept.
Also provides shared helpers for message operations and chat notifications."""

import logging
from datetime import datetime, timezone
from typing import Optional

from models import ChatConversation, ChatMessage, User

logger = logging.getLogger("event-booking.event_chat")


# ---------------------------------------------------------------------------
# Event-thread helpers (existing)
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# Message helpers (new)
# ---------------------------------------------------------------------------

def build_last_message_snapshot(message: ChatMessage) -> dict:
    """Create a compact snapshot dict stored on the conversation for quick listing."""
    text = (message.content or "")[:120]
    if getattr(message, "deleted_for_everyone", False):
        text = "This message was deleted"
    return {
        "text": text,
        "sender_id": message.sender_id,
        "sender_name": message.sender_name,
        "created_at": message.created_at.isoformat() if message.created_at else None,
        "message_id": str(message.id),
    }


async def increment_participant_unreads(
    conversation: ChatConversation,
    sender_id: str,
) -> None:
    """Bump unread counter for every participant except the sender."""
    unreads = dict(conversation.participant_unreads or {})
    for pid in conversation.participants:
        if pid == sender_id:
            unreads[pid] = 0
            continue
        unreads[pid] = unreads.get(pid, 0) + 1
    conversation.participant_unreads = unreads


async def reset_unread_for_user(
    conversation: ChatConversation,
    user_id: str,
) -> None:
    """Set unread count to 0 for a specific participant."""
    unreads = dict(conversation.participant_unreads or {})
    unreads[user_id] = 0
    conversation.participant_unreads = unreads


# ---------------------------------------------------------------------------
# Notification helper (new — email-based via existing notification system)
# ---------------------------------------------------------------------------

async def notify_new_message(
    conversation: ChatConversation,
    message: ChatMessage,
) -> None:
    """Send a lightweight email notification to all participants except the sender.

    Uses the existing `send_notification_email` helper.  Failures are logged
    but never propagated — chat must keep working even if email delivery fails.
    """
    try:
        from notifications import send_notification_email

        sender = await User.get(message.sender_id)
        if not sender:
            return

        preview = (message.content or "")[:200]
        conv_label = conversation.title or "a conversation"
        subject = f"New message from {message.sender_name}"
        body = (
            f"{message.sender_name} sent a message in {conv_label}:\n\n"
            f"\"{preview}\"\n\n"
            f"Open the Event Booking portal to reply."
        )

        for pid in conversation.participants:
            if pid == message.sender_id:
                continue
            recipient = await User.get(pid)
            if not recipient or not recipient.email:
                continue
            try:
                await send_notification_email(
                    recipient_email=recipient.email,
                    subject=subject,
                    body=body,
                    requester=sender,
                    fallback_role="registrar",
                )
            except Exception as exc:
                logger.warning(
                    "notify_new_message: email to %s failed: %s",
                    recipient.email,
                    exc,
                )
    except Exception as exc:
        logger.warning("notify_new_message: unexpected error: %s", exc)
