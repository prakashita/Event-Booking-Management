import json
import os
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from beanie import PydanticObjectId
from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, WebSocket, WebSocketDisconnect, status
from fastapi.responses import JSONResponse

from auth import decode_access_token
from models import ChatAttachment, ChatConversation, ChatMessage, User
from routers.deps import get_current_user
from schemas import (
    ChatConversationCreate,
    ChatConversationResponse,
    ChatMessageCreate,
    ChatMessageResponse,
    ChatReadReceipt,
    ChatUploadResponse,
    ChatUserResponse,
)

router = APIRouter(prefix="/chat", tags=["chat"])

UPLOADS_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "uploads"))
os.makedirs(UPLOADS_DIR, exist_ok=True)


def serialize_message(message: ChatMessage) -> ChatMessageResponse:
    created_at = message.created_at
    if created_at and created_at.tzinfo is None:
        created_at = created_at.replace(tzinfo=timezone.utc)
    return ChatMessageResponse(
        id=str(message.id),
        conversation_id=message.conversation_id,
        sender_id=message.sender_id,
        sender_name=message.sender_name,
        sender_email=message.sender_email,
        content=message.content,
        attachments=message.attachments,
        read_by=message.read_by,
        created_at=created_at,
    )


def serialize_conversation(conversation: ChatConversation) -> ChatConversationResponse:
    return ChatConversationResponse(
        id=str(conversation.id),
        participants=conversation.participants,
        updated_at=conversation.updated_at,
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
        conversation = ChatConversation(participants=participants)
        await conversation.insert()
    return conversation


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
    conversation = await ChatConversation.get(conversation_id)
    if not conversation or str(current_user.id) not in conversation.participants:
        raise HTTPException(status_code=404, detail="Conversation not found")

    query = ChatMessage.find(ChatMessage.conversation_id == conversation_id)
    if before:
        query = ChatMessage.find(
            (ChatMessage.conversation_id == conversation_id) & (ChatMessage.created_at < before)
        )
    messages = await query.sort("-created_at").limit(limit).to_list()
    messages.reverse()
    return [serialize_message(msg) for msg in messages]


@router.post("/messages", response_model=ChatMessageResponse)
async def create_message(
    payload: ChatMessageCreate,
    current_user: User = Depends(get_current_user),
):
    if not payload.content and not payload.attachments:
        raise HTTPException(status_code=400, detail="Message cannot be empty")
    conversation = await ChatConversation.get(payload.conversation_id)
    if not conversation or str(current_user.id) not in conversation.participants:
        raise HTTPException(status_code=404, detail="Conversation not found")
    message = ChatMessage(
        conversation_id=payload.conversation_id,
        sender_id=str(current_user.id),
        sender_name=current_user.name,
        sender_email=current_user.email,
        content=payload.content,
        attachments=[ChatAttachment(**item.model_dump()) for item in payload.attachments],
        read_by=[str(current_user.id)],
        created_at=datetime.now(timezone.utc),
    )
    await message.insert()
    conversation.updated_at = datetime.now(timezone.utc)
    await conversation.save()
    data = serialize_message(message)
    await manager.send_to_users(conversation.participants, {"type": "message", "message": data.model_dump()})
    return data


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
async def upload_attachment(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
):
    if not file.filename:
        raise HTTPException(status_code=400, detail="Missing filename")
    ext = os.path.splitext(file.filename)[1]
    safe_name = f"{uuid.uuid4().hex}{ext}"
    destination = os.path.join(UPLOADS_DIR, safe_name)
    content = await file.read()
    with open(destination, "wb") as out_file:
        out_file.write(content)
    attachment = ChatAttachment(
        name=file.filename,
        url=f"/uploads/{safe_name}",
        content_type=file.content_type or "application/octet-stream",
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
                conversation = await ChatConversation.get(conversation_id)
                if not conversation or str(user.id) not in conversation.participants:
                    continue
                client_id = data.get("client_id")
                content = (data.get("text") or "").strip()
                attachments = data.get("attachments") or []
                if not content and not attachments:
                    continue
                message = ChatMessage(
                    conversation_id=conversation_id,
                    sender_id=str(user.id),
                    sender_name=user.name,
                    sender_email=user.email,
                    content=content,
                    attachments=[ChatAttachment(**item) for item in attachments],
                    read_by=[str(user.id)],
                    created_at=datetime.now(timezone.utc),
                )
                await message.insert()
                conversation.updated_at = datetime.now(timezone.utc)
                await conversation.save()
                message_payload = serialize_message(message).model_dump()
                if client_id:
                    message_payload["client_id"] = client_id
                await manager.send_to_users(
                    conversation.participants,
                    {"type": "message", "message": message_payload},
                )
            elif event_type == "typing":
                conversation_id = data.get("conversation_id")
                if not conversation_id:
                    continue
                conversation = await ChatConversation.get(conversation_id)
                if not conversation or str(user.id) not in conversation.participants:
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
