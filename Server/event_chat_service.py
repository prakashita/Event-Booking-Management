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
# Approval-thread helpers (department ↔ faculty isolated conversations)
# ---------------------------------------------------------------------------

DEPARTMENT_LABELS = {
    "registrar": "Registrar",
    "facility_manager": "Facility",
    "marketing": "Marketing",
    "it": "IT",
    "transport": "Transport",
    "iqac": "IQAC",
}


async def get_approval_thread(
    approval_request_id: str,
    department: str,
    related_request_id: str | None = None,
) -> Optional[ChatConversation]:
    """Find an existing approval_thread conversation for a department+approval pair."""
    query: dict = {
        "thread_kind": "approval_thread",
        "approval_request_id": approval_request_id,
        "department": department,
    }
    if related_request_id:
        query["related_request_id"] = related_request_id
    return await ChatConversation.find_one(query)


async def ensure_approval_thread_chat(
    *,
    approval_request_id: str,
    department: str,
    faculty_user_id: str,
    department_user_id: str,
    related_request_id: str | None = None,
    related_kind: str = "approval_request",
    title: str = "",
    initial_message: str = "",
    sender_name: str = "",
    sender_email: str = "",
) -> ChatConversation:
    """Create or retrieve a 2-party approval thread between department and faculty.

    Optionally posts the first message (e.g. the clarification comment).
    """
    existing = await get_approval_thread(approval_request_id, department, related_request_id)
    if existing:
        # Ensure both participants are present
        merged = sorted(set(existing.participants + [faculty_user_id, department_user_id]))
        if merged != sorted(existing.participants):
            existing.participants = merged
            existing.updated_at = datetime.now(timezone.utc)
            await existing.save()
        return existing

    dept_label = DEPARTMENT_LABELS.get(department, department.title())
    participants = sorted({faculty_user_id, department_user_id})
    conv = ChatConversation(
        participants=list(participants),
        thread_kind="approval_thread",
        approval_request_id=approval_request_id,
        department=department,
        related_request_id=related_request_id or approval_request_id,
        related_kind=related_kind,
        thread_status="active",
        title=title or f"{dept_label} clarification",
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    await conv.insert()

    if initial_message and department_user_id and sender_name:
        msg = ChatMessage(
            conversation_id=str(conv.id),
            sender_id=department_user_id,
            sender_name=sender_name,
            sender_email=sender_email,
            content=initial_message.strip(),
            read_by=[department_user_id],
            created_at=datetime.now(timezone.utc),
        )
        await msg.insert()
        conv.last_message = build_last_message_snapshot(msg)
        conv.participant_unreads = {
            pid: (0 if pid == department_user_id else 1) for pid in participants
        }
        await conv.save()

    return conv


async def list_approval_threads(approval_request_id: str) -> list[ChatConversation]:
    """Return all approval_thread conversations tied to a given approval."""
    if not approval_request_id:
        return []
    return await ChatConversation.find(
        {
            "thread_kind": "approval_thread",
            "approval_request_id": approval_request_id,
        }
    ).sort("created_at").to_list()


async def ensure_dept_request_thread(
    *,
    approval_request_id: str,
    department: str,
    faculty_user_id: str,
    dept_email: str,
    related_request_id: str,
    related_kind: str,
    event_name: str,
) -> None:
    """Create (or retrieve) a discussion thread for a department request submitted by faculty.

    Looks up the department user by email.  Silently no-ops if the user isn't found or anything fails.
    """
    if not approval_request_id or not dept_email:
        return
    try:
        dept_user = await User.find_one({"email": dept_email.strip().lower()})
        if not dept_user:
            return
        dept_label = DEPARTMENT_LABELS.get(department, department.title())
        await ensure_approval_thread_chat(
            approval_request_id=approval_request_id,
            department=department,
            faculty_user_id=faculty_user_id,
            department_user_id=str(dept_user.id),
            related_request_id=related_request_id,
            related_kind=related_kind,
            title=f"{dept_label} – {event_name}",
            initial_message="",
            sender_name="",
            sender_email="",
        )
    except Exception as exc:
        logger.warning("ensure_dept_request_thread (%s): %s", department, exc)


async def resolve_approval_thread_status(
    approval_request_id: str,
    new_status: str,
) -> None:
    """Mark all threads for an approval as resolved when approved/rejected."""
    if new_status not in ("approved", "rejected"):
        return
    now = datetime.now(timezone.utc)
    threads = await list_approval_threads(approval_request_id)
    for t in threads:
        if (t.thread_status or "active") not in ("resolved", "closed"):
            t.thread_status = "resolved"
            t.closed_at = now
            t.closed_reason = new_status
            await t.save()


async def close_threads_for_request(
    approval_request_id: str,
    department: str,
    related_request_id: str,
    reason: str = "approved",
) -> None:
    """Close the specific dept thread when its individual request is finalized."""
    thread = await get_approval_thread(approval_request_id, department, related_request_id)
    if thread and (thread.thread_status or "active") not in ("resolved", "closed"):
        thread.thread_status = "resolved"
        thread.closed_at = datetime.now(timezone.utc)
        thread.closed_reason = reason
        await thread.save()


async def close_all_threads_for_approval(
    approval_request_id: str,
    reason: str = "event_closed",
) -> None:
    """Close all threads linked to an approval (e.g. when event is set to closed)."""
    now = datetime.now(timezone.utc)
    threads = await list_approval_threads(approval_request_id)
    for t in threads:
        if (t.thread_status or "active") not in ("resolved", "closed"):
            t.thread_status = "closed"
            t.closed_at = now
            t.closed_reason = reason
            await t.save()


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

async def notify_thread_reply(
    conversation: ChatConversation,
    message: ChatMessage,
    sender: "User",
    approval: "ApprovalRequest | None" = None,
) -> None:
    """Email other participant(s) when someone posts in an approval thread."""
    try:
        from notifications import send_notification_email

        dept_label = DEPARTMENT_LABELS.get(conversation.department or "", "Department")
        event_name = (getattr(approval, "event_name", None) or conversation.title or "Event")
        preview = (message.content or "")[:200]
        subject = f"New message on Event Approval – {event_name}"
        body = (
            f"{message.sender_name} sent a message in the {dept_label} discussion "
            f"for \"{event_name}\":\n\n"
            f"\"{preview}\"\n\n"
            f"Open the Event Booking portal to reply."
        )

        for pid in conversation.participants:
            if pid == str(sender.id):
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
                logger.warning("notify_thread_reply: email to %s failed: %s", recipient.email, exc)
    except Exception as exc:
        logger.warning("notify_thread_reply: unexpected error: %s", exc)


async def notify_legacy_discussion_reply(
    sender: "User",
    approval: "ApprovalRequest",
    message_text: str,
) -> None:
    """Email the other party (requester or registrar) when a reply is posted on the legacy discussion."""
    try:
        from notifications import send_notification_email

        is_from_requester = str(sender.id) == str(approval.requester_id)
        if is_from_requester:
            recipient_email = (approval.requested_to or "").strip()
            if not recipient_email:
                return
            recipient = await User.find_one(User.email == recipient_email)
        else:
            recipient = await User.get(approval.requester_id)

        if not recipient or not recipient.email:
            return

        event_name = approval.event_name or "Event"
        preview = (message_text or "")[:200]
        subject = f"New message on Event Approval – {event_name}"
        body = (
            f"{sender.name} replied on the Registrar discussion for \"{event_name}\":\n\n"
            f"\"{preview}\"\n\n"
            f"Open the Event Booking portal to reply."
        )
        await send_notification_email(
            recipient_email=recipient.email,
            subject=subject,
            body=body,
            requester=sender,
            fallback_role="registrar",
        )
    except Exception as exc:
        logger.warning("notify_legacy_discussion_reply: unexpected error: %s", exc)


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
