"""Shared email notification helpers."""
import base64
import logging

import requests

from auth import ensure_google_access_token, get_user_by_role

logger = logging.getLogger("event-booking.notifications")


def _build_raw_email(to_email: str, subject: str, body: str) -> str:
    headers = [
        f"To: {to_email}",
        f"Subject: {subject}",
        "Content-Type: text/plain; charset=\"UTF-8\"",
    ]
    return "\r\n".join(headers) + "\r\n\r\n" + body


async def send_notification_email(
    recipient_email: str,
    subject: str,
    body: str,
    requester,
    fallback_role: str | None = None,
) -> bool:
    """
    Send email to recipient. Tries requester's Gmail first, then user with fallback_role.
    Returns True if sent, False otherwise. Logs warning on failure, does not raise.
    requester: User model instance.
    """
    access_token = None
    candidates = [requester]
    if fallback_role:
        fallback_user = await get_user_by_role(fallback_role)
        if fallback_user and fallback_user.id != requester.id:
            candidates.append(fallback_user)

    for sender_user in candidates:
        if not sender_user:
            continue
        try:
            access_token = await ensure_google_access_token(sender_user)
            break
        except Exception:
            continue

    if not access_token:
        logger.warning("Cannot send notification: no Gmail available for requester or %s", fallback_role)
        return False

    raw_message = _build_raw_email(recipient_email, subject, body)
    encoded_message = base64.urlsafe_b64encode(raw_message.encode("utf-8")).decode("utf-8")
    response = requests.post(
        "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"raw": encoded_message},
        timeout=15,
    )
    if response.status_code not in {200, 202}:
        logger.warning("Failed to send notification to %s: %s", recipient_email, response.text)
        return False
    return True
