import base64

from fastapi import APIRouter, Depends, HTTPException, status
import requests

from auth import ensure_google_access_token
from models import Event, Invite, User
from routers.deps import get_current_user
from schemas import InviteCreate, InviteResponse

router = APIRouter(prefix="/invites", tags=["Invites"])


def build_raw_email(to_email: str, subject: str, body: str) -> str:
    headers = [
        f"To: {to_email}",
        f"Subject: {subject}",
        "Content-Type: text/plain; charset=\"UTF-8\"",
    ]
    return "\r\n".join(headers) + "\r\n\r\n" + body


@router.post("", response_model=InviteResponse, status_code=status.HTTP_201_CREATED)
async def send_invite(payload: InviteCreate, user: User = Depends(get_current_user)):
    event = await Event.get(payload.event_id)
    if not event:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")
    if event.created_by != str(user.id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed")

    access_token = await ensure_google_access_token(user)
    raw_message = build_raw_email(payload.to_email, payload.subject, payload.body)
    encoded_message = base64.urlsafe_b64encode(raw_message.encode("utf-8")).decode("utf-8")

    response = requests.post(
        "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"raw": encoded_message},
        timeout=15,
    )

    if response.status_code not in {200, 202}:
        detail = "Unable to send invite email"
        try:
            error_payload = response.json()
            detail = error_payload.get("error", {}).get("message", detail)
        except ValueError:
            if response.text:
                detail = response.text
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=detail,
        )

    invite = Invite(
        event_id=payload.event_id,
        created_by=str(user.id),
        to_email=payload.to_email,
        subject=payload.subject,
        body=payload.body,
        status="sent",
    )
    await invite.insert()

    return InviteResponse(
        id=str(invite.id),
        event_id=invite.event_id,
        created_by=invite.created_by,
        to_email=invite.to_email,
        subject=invite.subject,
        body=invite.body,
        status=invite.status,
        sent_at=invite.sent_at,
        created_at=invite.created_at,
    )


@router.get("/me", response_model=list[InviteResponse])
async def list_my_invites(user: User = Depends(get_current_user)):
    invites = await Invite.find(Invite.created_by == str(user.id)).sort("-created_at").to_list()
    return [
        InviteResponse(
            id=str(invite.id),
            event_id=invite.event_id,
            created_by=invite.created_by,
            to_email=invite.to_email,
            subject=invite.subject,
            body=invite.body,
            status=invite.status,
            sent_at=invite.sent_at,
            created_at=invite.created_at,
        )
        for invite in invites
    ]
