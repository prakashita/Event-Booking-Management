import json
import logging
import os
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from beanie import PydanticObjectId
from beanie.operators import In
from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, UploadFile, WebSocket, WebSocketDisconnect, status

from rate_limit import limiter
from fastapi.responses import JSONResponse

from auth import decode_access_token
from event_chat_service import (
    build_last_message_snapshot,
    increment_participant_unreads,
    notify_new_message,
    reset_unread_for_user,
)
from models import ChatAttachment, ChatConversation, ChatMessage, User
from routers.deps import can_view_conversation, get_current_user, require_conversation_access
from schemas import (
    ChatAttachment as ChatAttachmentResponse,
    ChatConversationCreate,
    ChatConversationListItem,
    ChatConversationResponse,
    ChatMessageCreate,
    ChatMessageEdit,
    ChatMessageResponse,
    ChatParticipantSummary,
    ChatReadReceipt,
    ChatSendMessage,
    ChatUploadResponse,
    ChatUserResponse,
)

logger = logging.getLogger("event-booking.chat")

router = APIRouter(prefix="/chat", tags=["chat"])

def resolve_uploads_dir() -> str:
    env_dir = os.getenv("UPLOADS_DIR")
    if env_dir:
        return os.path.abspath(env_dir)
    if os.getenv("VERCEL") == "1":
        return "/tmp/uploads"
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "uploads"))


UPLOADS_DIR = resolve_uploads_dir()
try:
    os.makedirs(UPLOADS_DIR, exist_ok=True)
except OSError:
    UPLOADS_DIR = "/tmp/uploads"
    os.makedirs(UPLOADS_DIR, exist_ok=True)

# ---------------------------------------------------------------------------
# Upload configuration — keep in sync with Client/src/constants/uploadConfig.js
# ---------------------------------------------------------------------------
MAX_CHAT_UPLOAD_BYTES = 5 * 1024 * 1024  # 5 MB
_CHAT_ALLOWED_CT_EXACT = frozenset(
    {
        "image/jpeg",
        "image/jpg",
        "image/png",
        "image/webp",
        "application/pdf",
    }
)

_CHAT_EXT_TO_MIME = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
    ".pdf": "application/pdf",
}


def _normalize_declared_chat_mime(content_type: str) -> str:
    ct = (content_type or "application/octet-stream").split(";")[0].strip().lower()
    if ct == "image/pjpeg":
        return "image/jpeg"
    return ct


def _mime_from_filename(filename: str) -> Optional[str]:
    ext = os.path.splitext(filename or "")[1].lower()
    return _CHAT_EXT_TO_MIME.get(ext)


def resolve_allowed_chat_mime(content_type: Optional[str], filename: str) -> Optional[str]:
    """
    Return a canonical allowed MIME, or None if the upload should be rejected.
    Accepts application/octet-stream (or empty) when the filename extension matches.
    """
    raw = (content_type or "application/octet-stream").split(";")[0].strip().lower()
    ct = _normalize_declared_chat_mime(raw)
    if ct in _CHAT_ALLOWED_CT_EXACT:
        return ct
    if raw in ("application/octet-stream", "", "binary/octet-stream"):
        guessed = _mime_from_filename(filename)
        if guessed:
            return guessed
    return None


async def _read_upload_bytes_capped(upload: UploadFile, max_bytes: int) -> tuple[Optional[bytes], Optional[str]]:
    """Read upload into memory with a hard cap; returns (data, error_message)."""
    chunks: List[bytes] = []
    total = 0
    while True:
        chunk = await upload.read(1024 * 1024)
        if not chunk:
            break
        total += len(chunk)
        if total > max_bytes:
            return None, "File size exceeds 5MB. Please upload a smaller file or share a Drive link."
        chunks.append(chunk)
    return b"".join(chunks), None


def serialize_message(
    message: ChatMessage,
    conversation: Optional[ChatConversation] = None,
) -> ChatMessageResponse:
    created_at = message.created_at
    if created_at and created_at.tzinfo is None:
        created_at = created_at.replace(tzinfo=timezone.utc)
    thread_kind = None
    if conversation is not None:
        thread_kind = getattr(conversation, "thread_kind", None) or "direct"

    # Handle deleted messages — replace content for everyone
    content = message.content
    is_deleted = getattr(message, "is_deleted", False)
    deleted_for_everyone = getattr(message, "deleted_for_everyone", False)
    if deleted_for_everyone:
        content = "This message was deleted"

    edited = bool(getattr(message, "edited", False)) and not deleted_for_everyone
    edited_at = getattr(message, "edited_at", None)
    if deleted_for_everyone:
        edited = False
        edited_at = None
    if edited_at and edited_at.tzinfo is None:
        edited_at = edited_at.replace(tzinfo=timezone.utc)

    return ChatMessageResponse(
        id=str(message.id),
        conversation_id=message.conversation_id,
        sender_id=message.sender_id,
        sender_name=message.sender_name,
        sender_email=message.sender_email,
        content=content,
        attachments=[] if deleted_for_everyone else message.attachments,
        read_by=message.read_by,
        created_at=created_at,
        conversation_thread_kind=thread_kind,
        is_deleted=is_deleted,
        deleted_for_everyone=deleted_for_everyone,
        edited=edited,
        edited_at=edited_at,
        reply_to_message_id=getattr(message, "reply_to_message_id", None),
        reply_to_snapshot=getattr(message, "reply_to_snapshot", None),
    )


def serialize_conversation(conversation: ChatConversation) -> ChatConversationResponse:
    return ChatConversationResponse(
        id=str(conversation.id),
        participants=conversation.participants,
        updated_at=conversation.updated_at,
        thread_kind=getattr(conversation, "thread_kind", None) or "direct",
        event_id=getattr(conversation, "event_id", None),
        title=getattr(conversation, "title", None),
    )


class ConnectionManager:
    def __init__(self) -> None:
        self.active: Dict[str, WebSocket] = {}

    async def connect(self, websocket: WebSocket, user: User) -> None:
        await websocket.accept()
        self.active[str(user.id)] = websocket
        await self.broadcast(
            {
                "type": "presence",
                "user_id": str(user.id),
                "online": True,
                "last_seen": None,
            }
        )

    async def disconnect(self, user: User) -> None:
        self.active.pop(str(user.id), None)
        user.last_seen = datetime.now(timezone.utc)
        await user.save()
        await self.broadcast(
            {
                "type": "presence",
                "user_id": str(user.id),
                "online": False,
                "last_seen": user.last_seen.isoformat(),
            }
        )

    def is_online(self, user_id: str) -> bool:
        return user_id in self.active

    async def broadcast(self, payload: Dict[str, Any]) -> None:
        dead_connections = []
        for user_id, websocket in self.active.items():
            try:
                await websocket.send_json(payload)
            except Exception:
                dead_connections.append(user_id)
        for user_id in dead_connections:
            self.active.pop(user_id, None)

    async def send_to_users(self, user_ids: List[str], payload: Dict[str, Any]) -> None:
        dead_connections = []
        for user_id in user_ids:
            websocket = self.active.get(user_id)
            if not websocket:
                continue
            try:
                await websocket.send_json(payload)
            except Exception:
                dead_connections.append(user_id)
        for user_id in dead_connections:
            self.active.pop(user_id, None)


manager = ConnectionManager()


async def get_user_from_token(token: str) -> User:
    if not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing token")
    payload = decode_access_token(token)
    user_id = payload.get("user_id")
    if not user_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    user = await User.get(user_id)
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    return user


async def get_or_create_conversation(user_a: str, user_b: str) -> ChatConversation:
    participants = sorted([user_a, user_b])
    conversation = await ChatConversation.find(
        {"participants": {"$all": participants, "$size": 2}}
    ).sort("-updated_at").first_or_none()
    if not conversation:
        conversation = ChatConversation(participants=participants, thread_kind="direct")
        await conversation.insert()
    return conversation


async def get_chat_message_by_id(message_id: str) -> Optional[ChatMessage]:
    try:
        return await ChatMessage.get(PydanticObjectId(message_id))
    except Exception:
        return None


async def _resolve_reply_snapshot(
    reply_to_message_id: Optional[str],
    conversation_id: str,
) -> tuple[Optional[str], Optional[dict]]:
    """Resolve and freeze a reply snapshot for a given parent message id.

    Returns (canonical_id, snapshot_dict) or (None, None) if not applicable.
    The snapshot is frozen at write time so it survives future edits/deletes.
    """
    if not reply_to_message_id:
        return None, None
    try:
        orig = await ChatMessage.get(PydanticObjectId(reply_to_message_id))
        if not orig or orig.conversation_id != conversation_id:
            return None, None
        if getattr(orig, "deleted_for_everyone", False):
            snapshot = {
                "sender_name": orig.sender_name,
                "content_preview": "[Original message was deleted]",
                "is_deleted": True,
            }
        else:
            snapshot = {
                "sender_name": orig.sender_name,
                "content_preview": (orig.content or "")[:120],
                "is_deleted": False,
            }
        return str(orig.id), snapshot
    except Exception:
        return None, None


@router.get("/conversations/me", response_model=list[ChatConversationListItem])
async def list_my_conversations(
    current_user: User = Depends(get_current_user),
    search: Optional[str] = Query(default=None, max_length=200),
    unread_only: bool = Query(default=False),
    event_id: Optional[str] = Query(default=None),
):
    from event_chat_service import DEPARTMENT_LABELS

    uid = str(current_user.id)

    # Base filter: user is participant AND hasn't soft-deleted
    base_filter: Dict[str, Any] = {
        "participants": uid,
        "deleted_for": {"$nin": [uid]},
    }
    if event_id:
        base_filter["event_id"] = event_id

    convs = await ChatConversation.find(base_filter).sort("-updated_at").to_list()

    # Batch-resolve participant display names
    participant_oids: List[PydanticObjectId] = []
    seen_oid: set[str] = set()
    for conv in convs:
        for pid in conv.participants:
            try:
                oid = PydanticObjectId(pid)
            except Exception:
                continue
            key = str(oid)
            if key not in seen_oid:
                seen_oid.add(key)
                participant_oids.append(oid)
    users_by_id: Dict[str, User] = {}
    if participant_oids:
        for u in await User.find(In(User.id, participant_oids)).to_list():
            users_by_id[str(u.id)] = u

    items: List[ChatConversationListItem] = []
    for conv in convs:
        kind = getattr(conv, "thread_kind", None) or "direct"
        unreads = (getattr(conv, "participant_unreads", None) or {})
        unread_count = unreads.get(uid, 0)

        # Filter: unread_only
        if unread_only and unread_count == 0:
            continue

        # Filter: search — match conversation title, other user name, or last message text
        if search:
            q = search.lower()
            title_match = (getattr(conv, "title", None) or "").lower()
            lm = getattr(conv, "last_message", None) or {}
            lm_text = (lm.get("text") or "").lower()
            matched = q in title_match or q in lm_text
            # Also check other user name in direct threads
            if not matched and kind == "direct" and len(conv.participants) == 2:
                other_id = next((p for p in conv.participants if p != uid), None)
                if other_id:
                    ou = await User.get(other_id)
                    if ou and q in (ou.name or "").lower():
                        matched = True
            if not matched:
                continue

        other = None
        if kind == "direct" and len(conv.participants) == 2:
            other_id = next((p for p in conv.participants if p != uid), None)
            if other_id:
                ou = await User.get(other_id)
                if ou:
                    other = ChatUserResponse(
                        id=str(ou.id),
                        name=ou.name,
                        email=ou.email,
                        role=ou.role,
                        online=manager.is_online(str(ou.id)),
                        last_seen=ou.last_seen,
                    )
        preview_list: List[ChatParticipantSummary] = []
        for pid in conv.participants:
            u = users_by_id.get(pid)
            if u:
                preview_list.append(
                    ChatParticipantSummary(id=pid, name=u.name or "Unknown"),
                )
        preview_list.sort(key=lambda s: (s.name or "").lower())

        dept = getattr(conv, "department", None)
        dept_label = DEPARTMENT_LABELS.get(dept or "", None) if dept else None

        items.append(
            ChatConversationListItem(
                id=str(conv.id),
                thread_kind=kind,
                participants=list(conv.participants),
                updated_at=conv.updated_at,
                title=getattr(conv, "title", None),
                event_id=getattr(conv, "event_id", None),
                other_user=other,
                unread_count=unread_count,
                last_message=getattr(conv, "last_message", None),
                participant_count=len(conv.participants),
                participants_preview=preview_list,
                thread_status=getattr(conv, "thread_status", None),
                department=dept,
                department_label=dept_label,
                related_kind=getattr(conv, "related_kind", None),
                approval_request_id=getattr(conv, "approval_request_id", None),
                closed_at=getattr(conv, "closed_at", None),
                closed_reason=getattr(conv, "closed_reason", None),
            )
        )
    return items


@router.get("/users", response_model=list[ChatUserResponse])
async def get_chat_users(current_user: User = Depends(get_current_user)):
    users = await User.find(User.id != current_user.id).sort("name").to_list()
    return [
        ChatUserResponse(
            id=str(user.id),
            name=user.name,
            email=user.email,
            role=user.role,
            online=manager.is_online(str(user.id)),
            last_seen=user.last_seen,
        )
        for user in users
    ]


@router.post("/conversations", response_model=ChatConversationResponse)
async def create_conversation(
    payload: ChatConversationCreate,
    current_user: User = Depends(get_current_user),
):
    other_user = await User.get(payload.user_id)
    if not other_user:
        raise HTTPException(status_code=404, detail="User not found")
    conversation = await get_or_create_conversation(str(current_user.id), str(other_user.id))
    return serialize_conversation(conversation)


@router.get("/conversations/{conversation_id}/messages", response_model=list[ChatMessageResponse])
async def get_messages(
    conversation_id: str,
    limit: int = Query(default=50, ge=1, le=200),
    before: Optional[datetime] = Query(default=None),
    current_user: User = Depends(get_current_user),
):
    conversation = await require_conversation_access(current_user, conversation_id)

    uid = str(current_user.id)
    # Hide messages this user removed for themselves; still show "deleted for everyone" tombstones
    filters: Dict[str, Any] = {
        "conversation_id": conversation_id,
        "$or": [
            {"deleted_for": {"$exists": False}},
            {"deleted_for": {"$nin": [uid]}},
        ],
    }
    if before:
        filters["created_at"] = {"$lt": before}

    messages = await ChatMessage.find(filters).sort("-created_at").limit(limit).to_list()
    messages.reverse()
    return [serialize_message(msg, conversation) for msg in messages]


@router.post("/messages", response_model=ChatMessageResponse)
async def create_message(
    payload: ChatMessageCreate,
    current_user: User = Depends(get_current_user),
):
    if not payload.content and not payload.attachments:
        raise HTTPException(status_code=400, detail="Message cannot be empty")
    conversation = await require_conversation_access(current_user, payload.conversation_id, write=True)

    reply_id, reply_snapshot = await _resolve_reply_snapshot(
        getattr(payload, "reply_to_message_id", None), payload.conversation_id
    )

    message = ChatMessage(
        conversation_id=payload.conversation_id,
        sender_id=str(current_user.id),
        sender_name=current_user.name,
        sender_email=current_user.email,
        content=payload.content,
        attachments=[ChatAttachment(**item.model_dump()) for item in payload.attachments],
        read_by=[str(current_user.id)],
        created_at=datetime.now(timezone.utc),
        reply_to_message_id=reply_id,
        reply_to_snapshot=reply_snapshot,
    )
    await message.insert()

    # Update conversation metadata
    now = datetime.now(timezone.utc)
    conversation.updated_at = now
    conversation.last_message = build_last_message_snapshot(message)
    await increment_participant_unreads(conversation, str(current_user.id))
    await conversation.save()

    data = serialize_message(message, conversation)
    await manager.send_to_users(conversation.participants, {"type": "message", "message": data.model_dump()})

    # Fire-and-forget email notification
    try:
        await notify_new_message(conversation, message)
    except Exception as exc:
        logger.warning("create_message: notification error: %s", exc)

    return data


# ---------------------------------------------------------------------------
# POST /chat/send — unified send (create-or-fetch conversation + store message)
# ---------------------------------------------------------------------------

@router.post("/send", response_model=ChatMessageResponse)
async def send_message(
    payload: ChatSendMessage,
    current_user: User = Depends(get_current_user),
):
    """Send a message.  Provide *either* ``conversation_id`` (for an existing
    conversation) **or** ``recipient_id`` (to auto-create/fetch a 1-1 thread).
    """
    if not payload.content and not payload.attachments:
        raise HTTPException(status_code=400, detail="Message cannot be empty")

    uid = str(current_user.id)

    # Resolve conversation
    conversation: Optional[ChatConversation] = None
    if payload.conversation_id:
        conversation = await ChatConversation.get(payload.conversation_id)
        if not conversation or uid not in conversation.participants:
            raise HTTPException(status_code=404, detail="Conversation not found")
    elif payload.recipient_id:
        other = await User.get(payload.recipient_id)
        if not other:
            raise HTTPException(status_code=404, detail="Recipient not found")
        conversation = await get_or_create_conversation(uid, str(other.id))
    else:
        raise HTTPException(status_code=400, detail="Provide conversation_id or recipient_id")

    message = ChatMessage(
        conversation_id=str(conversation.id),
        sender_id=uid,
        sender_name=current_user.name,
        sender_email=current_user.email,
        content=payload.content,
        attachments=[ChatAttachment(**a.model_dump()) for a in payload.attachments],
        read_by=[uid],
        created_at=datetime.now(timezone.utc),
    )
    await message.insert()

    # Update conversation metadata
    now = datetime.now(timezone.utc)
    conversation.updated_at = now
    conversation.last_message = build_last_message_snapshot(message)
    await increment_participant_unreads(conversation, uid)
    await conversation.save()

    data = serialize_message(message, conversation)
    await manager.send_to_users(conversation.participants, {"type": "message", "message": data.model_dump()})

    # Fire-and-forget notification
    try:
        await notify_new_message(conversation, message)
    except Exception as exc:
        logger.warning("send_message: notification error: %s", exc)

    return data


# ---------------------------------------------------------------------------
# POST /chat/read/{conversation_id} — mark conversation as read for user
# ---------------------------------------------------------------------------

@router.post("/read/{conversation_id}")
async def mark_conversation_read(
    conversation_id: str,
    current_user: User = Depends(get_current_user),
):
    """Reset unread count for the current user in the given conversation and
    mark all messages in it as read by this user."""
    uid = str(current_user.id)
    conversation = await require_conversation_access(current_user, conversation_id)

    # Reset unread counter
    await reset_unread_for_user(conversation, uid)
    await conversation.save()

    # Bulk-mark all unread messages as read
    result = await ChatMessage.find(
        {
            "conversation_id": conversation_id,
            "read_by": {"$nin": [uid]},
        }
    ).update({"$addToSet": {"read_by": uid}})

    # Notify via WebSocket so other clients update read receipts
    await manager.send_to_users(
        conversation.participants,
        {"type": "read_conversation", "conversation_id": conversation_id, "user_id": uid},
    )

    updated = result.modified_count if hasattr(result, "modified_count") else 0
    return JSONResponse({"updated": updated, "conversation_id": conversation_id})


# ---------------------------------------------------------------------------
# DELETE /chat/message/{message_id} — delete for everyone
# ---------------------------------------------------------------------------

@router.delete("/message/{message_id}")
async def delete_message(
    message_id: str,
    current_user: User = Depends(get_current_user),
):
    """Mark a message as deleted for everyone.  Only the message sender may
    delete.  The content is replaced with a tombstone string."""
    uid = str(current_user.id)
    msg = await get_chat_message_by_id(message_id)
    if not msg:
        raise HTTPException(status_code=404, detail="Message not found")
    if msg.sender_id != uid:
        raise HTTPException(status_code=403, detail="Only the sender can delete a message")

    msg.is_deleted = True
    msg.deleted_for_everyone = True
    msg.content = "This message was deleted"
    msg.attachments = []
    await msg.save()

    # If this was the last_message on the conversation, update the snapshot
    conversation = await ChatConversation.get(msg.conversation_id)
    if conversation:
        lm = getattr(conversation, "last_message", None) or {}
        mid = str(msg.id)
        if lm.get("message_id") == mid or (
            not lm.get("message_id")
            and lm.get("created_at")
            and msg.created_at
            and lm["created_at"] == msg.created_at.isoformat()
            and lm.get("sender_id") == uid
        ):
            conversation.last_message = build_last_message_snapshot(msg)
            await conversation.save()

        # Notify participants via WebSocket
        await manager.send_to_users(
            conversation.participants,
            {
                "type": "message_deleted",
                "message_id": message_id,
                "conversation_id": msg.conversation_id,
                "message": serialize_message(msg, conversation).model_dump(),
            },
        )

    return JSONResponse({"deleted": True, "message_id": message_id})


# ---------------------------------------------------------------------------
# PATCH /chat/message/{message_id} — edit (sender only)
# ---------------------------------------------------------------------------


@router.patch("/message/{message_id}", response_model=ChatMessageResponse)
async def edit_message(
    message_id: str,
    payload: ChatMessageEdit,
    current_user: User = Depends(get_current_user),
):
    uid = str(current_user.id)
    msg = await get_chat_message_by_id(message_id)
    if not msg:
        raise HTTPException(status_code=404, detail="Message not found")
    if msg.sender_id != uid:
        raise HTTPException(status_code=403, detail="Only the sender can edit this message")
    if msg.deleted_for_everyone:
        raise HTTPException(status_code=400, detail="Cannot edit a deleted message")

    text = payload.content.strip()
    if not text and not (msg.attachments or []):
        raise HTTPException(status_code=400, detail="Message cannot be empty")

    msg.content = text
    msg.edited = True
    msg.edited_at = datetime.now(timezone.utc)
    await msg.save()

    conversation = await require_conversation_access(current_user, msg.conversation_id)

    lm = getattr(conversation, "last_message", None) or {}
    mid = str(msg.id)
    if lm.get("message_id") == mid or (
        not lm.get("message_id")
        and lm.get("created_at")
        and msg.created_at
        and lm["created_at"] == msg.created_at.isoformat()
        and lm.get("sender_id") == uid
    ):
        conversation.last_message = build_last_message_snapshot(msg)
        await conversation.save()

    data = serialize_message(msg, conversation)
    await manager.send_to_users(
        conversation.participants,
        {"type": "message_edited", "message": data.model_dump()},
    )
    return data


# ---------------------------------------------------------------------------
# POST /chat/message/{message_id}/delete-for-me
# ---------------------------------------------------------------------------


@router.post("/message/{message_id}/delete-for-me")
async def delete_message_for_me(
    message_id: str,
    current_user: User = Depends(get_current_user),
):
    uid = str(current_user.id)
    msg = await get_chat_message_by_id(message_id)
    if not msg:
        raise HTTPException(status_code=404, detail="Message not found")
    conversation = await require_conversation_access(current_user, msg.conversation_id)

    deleted_for = list(getattr(msg, "deleted_for", None) or [])
    if uid not in deleted_for:
        deleted_for.append(uid)
        msg.deleted_for = deleted_for
        await msg.save()

    await manager.send_to_users(
        [uid],
        {
            "type": "message_hidden",
            "message_id": message_id,
            "conversation_id": msg.conversation_id,
        },
    )
    return JSONResponse({"ok": True, "message_id": message_id})


# ---------------------------------------------------------------------------
# POST /chat/conversations/{conversation_id}/clear — remove all messages
# ---------------------------------------------------------------------------


@router.post("/conversations/{conversation_id}/clear")
async def clear_conversation_messages(
    conversation_id: str,
    current_user: User = Depends(get_current_user),
):
    uid = str(current_user.id)
    conversation = await require_conversation_access(current_user, conversation_id)

    await ChatMessage.find(ChatMessage.conversation_id == conversation_id).delete()
    conversation.last_message = None
    unreads = {pid: 0 for pid in conversation.participants}
    conversation.participant_unreads = unreads
    conversation.updated_at = datetime.now(timezone.utc)
    await conversation.save()

    await manager.send_to_users(
        conversation.participants,
        {"type": "conversation_cleared", "conversation_id": conversation_id},
    )
    return JSONResponse({"cleared": True, "conversation_id": conversation_id})


# ---------------------------------------------------------------------------
# POST /chat/conversations/{conversation_id}/purge — delete thread + messages
# ---------------------------------------------------------------------------


@router.post("/conversations/{conversation_id}/purge")
async def purge_conversation(
    conversation_id: str,
    current_user: User = Depends(get_current_user),
):
    uid = str(current_user.id)
    conversation = await require_conversation_access(current_user, conversation_id)

    participants = list(conversation.participants)
    cid = str(conversation.id)
    await ChatMessage.find(ChatMessage.conversation_id == cid).delete()
    await conversation.delete()

    await manager.send_to_users(
        participants,
        {"type": "conversation_deleted", "conversation_id": cid},
    )
    return JSONResponse({"deleted": True, "conversation_id": cid})


# ---------------------------------------------------------------------------
# DELETE /chat/conversation/{conversation_id} — soft delete per user
# ---------------------------------------------------------------------------

@router.delete("/conversation/{conversation_id}")
async def delete_conversation(
    conversation_id: str,
    current_user: User = Depends(get_current_user),
):
    """Soft-delete a conversation for the current user.  The conversation is
    hidden from the user's list but remains for other participants."""
    uid = str(current_user.id)
    conversation = await require_conversation_access(current_user, conversation_id)

    deleted_for = list(getattr(conversation, "deleted_for", None) or [])
    if uid not in deleted_for:
        deleted_for.append(uid)
        conversation.deleted_for = deleted_for
        await conversation.save()

    return JSONResponse({"deleted": True, "conversation_id": conversation_id})


# ---------------------------------------------------------------------------
# Existing read-receipt endpoint (backward compatible)
# ---------------------------------------------------------------------------

@router.post("/read")
async def mark_read(
    payload: ChatReadReceipt,
    current_user: User = Depends(get_current_user),
):
    if not payload.message_ids:
        return JSONResponse({"updated": 0})
    object_ids: List[PydanticObjectId] = []
    for message_id in payload.message_ids:
        try:
            object_ids.append(PydanticObjectId(message_id))
        except Exception:
            continue
    if not object_ids:
        return JSONResponse({"updated": 0})

    result = await ChatMessage.find({"_id": {"$in": object_ids}}).update(
        {"$addToSet": {"read_by": str(current_user.id)}}
    )
    messages = await ChatMessage.find({"_id": {"$in": object_ids}}).to_list()
    conversation_ids = {msg.conversation_id for msg in messages}
    for conversation_id in conversation_ids:
        conversation = await ChatConversation.get(conversation_id)
        if not conversation:
            continue
        await manager.send_to_users(
            conversation.participants,
            {"type": "read", "message_ids": payload.message_ids, "user_id": str(current_user.id)},
        )
    return JSONResponse({"updated": result.modified_count if hasattr(result, "modified_count") else 0})


@router.post("/upload", response_model=ChatUploadResponse)
@limiter.limit("30/minute")
async def upload_attachment(
    request: Request,
    current_user: User = Depends(get_current_user),
    file: UploadFile = File(...),
):
    if not file.filename:
        return JSONResponse(
            status_code=400,
            content={"success": False, "message": "Missing filename."},
        )

    canonical_mime = resolve_allowed_chat_mime(file.content_type, file.filename)
    if not canonical_mime:
        return JSONResponse(
            status_code=400,
            content={
                "success": False,
                "message": "Unsupported file type. Please upload an image (JPEG, PNG, WebP) or PDF only.",
            },
        )

    content, size_err = await _read_upload_bytes_capped(file, MAX_CHAT_UPLOAD_BYTES)
    if size_err or content is None:
        return JSONResponse(
            status_code=400,
            content={"success": False, "message": size_err or "Could not read the uploaded file."},
        )

    ext = os.path.splitext(file.filename)[1]
    safe_name = f"{uuid.uuid4().hex}{ext}"
    destination = os.path.join(UPLOADS_DIR, safe_name)
    try:
        with open(destination, "wb") as out_file:
            out_file.write(content)
    except OSError as exc:
        logger.exception("chat upload: failed to write file path=%s err=%s", destination, exc)
        return JSONResponse(
            status_code=507,
            content={
                "success": False,
                "message": "Could not save the file on the server. Ask an admin to check disk space and upload permissions.",
            },
        )

    attachment = ChatAttachmentResponse(
        name=file.filename,
        url=f"/uploads/{safe_name}",
        content_type=canonical_mime,
        size=len(content),
    )
    return ChatUploadResponse(attachment=attachment)


@router.websocket("/ws")
async def websocket_chat(websocket: WebSocket, token: Optional[str] = Query(default=None)):
    try:
        user = await get_user_from_token(token or "")
    except HTTPException:
        await websocket.close(code=1008)
        return

    await manager.connect(websocket, user)
    try:
        while True:
            payload = await websocket.receive_text()
            try:
                data = json.loads(payload)
            except json.JSONDecodeError:
                continue

            event_type = data.get("type")
            if event_type == "message":
                conversation_id = data.get("conversation_id")
                if not conversation_id:
                    continue
                try:
                    conversation = await ChatConversation.get(conversation_id)
                except Exception:
                    continue
                if not conversation or not can_view_conversation(user, conversation):
                    continue
                # Block sending to closed/resolved workflow threads
                if (
                    getattr(conversation, "thread_kind", None) == "approval_thread"
                    and getattr(conversation, "thread_status", None) in ("resolved", "closed")
                ):
                    continue
                if str(user.id) not in conversation.participants:
                    continue
                client_id = data.get("client_id")
                content = (data.get("text") or "").strip()
                attachments = data.get("attachments") or []
                if not content and not attachments:
                    continue
                # Resolve reply snapshot for WS path
                ws_reply_id, ws_reply_snapshot = await _resolve_reply_snapshot(
                    data.get("reply_to_message_id"), conversation_id
                )
                message = ChatMessage(
                    conversation_id=conversation_id,
                    sender_id=str(user.id),
                    sender_name=user.name,
                    sender_email=user.email,
                    content=content,
                    attachments=[ChatAttachment(**item) for item in attachments],
                    read_by=[str(user.id)],
                    created_at=datetime.now(timezone.utc),
                    reply_to_message_id=ws_reply_id,
                    reply_to_snapshot=ws_reply_snapshot,
                )
                await message.insert()

                # Update conversation metadata (last_message + unreads)
                conversation.updated_at = datetime.now(timezone.utc)
                conversation.last_message = build_last_message_snapshot(message)
                await increment_participant_unreads(conversation, str(user.id))
                await conversation.save()

                message_payload = serialize_message(message, conversation).model_dump()
                if client_id:
                    message_payload["client_id"] = client_id
                await manager.send_to_users(
                    conversation.participants,
                    {"type": "message", "message": message_payload},
                )

                # Fire-and-forget notification
                try:
                    await notify_new_message(conversation, message)
                except Exception:
                    pass
            elif event_type == "typing":
                conversation_id = data.get("conversation_id")
                if not conversation_id:
                    continue
                try:
                    conversation = await ChatConversation.get(conversation_id)
                except Exception:
                    continue
                if not conversation or not can_view_conversation(user, conversation):
                    continue
                is_typing = bool(data.get("is_typing"))
                recipients = [uid for uid in conversation.participants if uid != str(user.id)]
                await manager.send_to_users(
                    recipients,
                    {
                        "type": "typing",
                        "conversation_id": conversation_id,
                        "user_id": str(user.id),
                        "user_name": user.name,
                        "is_typing": is_typing,
                    },
                )
            elif event_type == "read":
                message_ids = data.get("message_ids") or []
                if message_ids:
                    object_ids = []
                    for message_id in message_ids:
                        try:
                            object_ids.append(PydanticObjectId(message_id))
                        except Exception:
                            continue
                    if object_ids:
                        await ChatMessage.find({"_id": {"$in": object_ids}}).update(
                            {"$addToSet": {"read_by": str(user.id)}}
                        )
                        messages = await ChatMessage.find({"_id": {"$in": object_ids}}).to_list()
                        conversation_ids = {msg.conversation_id for msg in messages}
                        for conversation_id in conversation_ids:
                            conversation = await ChatConversation.get(conversation_id)
                            if not conversation:
                                continue
                            await manager.send_to_users(
                                conversation.participants,
                                {"type": "read", "message_ids": message_ids, "user_id": str(user.id)},
                            )
    except WebSocketDisconnect:
        await manager.disconnect(user)
    except Exception:
        await manager.disconnect(user)
        await websocket.close(code=1011)
