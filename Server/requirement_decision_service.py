"""Apply department requirement decisions with workflow logging."""

import logging
from datetime import datetime
from typing import Union

from models import ApprovalRequest, FacilityManagerRequest, ItRequest, MarketingRequest, TransportRequest, User
from decision_helpers import action_type_for_status
from workflow_action_service import record_workflow_action

RequirementDoc = Union[FacilityManagerRequest, ItRequest, MarketingRequest, TransportRequest]

logger = logging.getLogger("event-booking.requirement-decision")


async def approval_request_id_for_event(event_id: str | None) -> str | None:
    if not event_id:
        return None
    ar = await ApprovalRequest.find_one(ApprovalRequest.event_id == event_id)
    return str(ar.id) if ar else None


async def apply_requirement_decision(
    request_item: RequirementDoc,
    *,
    user: User,
    normalized_status: str,
    comment: str,
    related_kind: str,
    role: str,
) -> bool:
    """
    Update a pending or clarification_requested row and append an audit log.
    Returns False if the row was already approved/rejected (idempotent, no new log).
    """
    if request_item.status in ("approved", "rejected"):
        return False
    if request_item.status not in ("pending", "clarification_requested"):
        return False

    request_item.status = normalized_status
    request_item.decided_by = user.email
    request_item.decided_at = datetime.utcnow()
    await request_item.save()

    ar_id = await approval_request_id_for_event(request_item.event_id)
    await record_workflow_action(
        event_id=request_item.event_id,
        approval_request_id=ar_id,
        related_kind=related_kind,
        related_id=str(request_item.id),
        role=role,
        action_type=action_type_for_status(normalized_status),
        comment=comment,
        action_by_email=user.email or "",
        action_by_user_id=str(user.id),
    )
    if normalized_status == "approved" and request_item.event_id:
        try:
            from event_chat_service import add_participant_to_event_chat

            await add_participant_to_event_chat(request_item.event_id, str(user.id))
        except Exception:
            pass

    # Notify requester via email when department requests clarification
    if normalized_status == "clarification_requested":
        try:
            from notifications import send_notification_email
            from event_chat_service import DEPARTMENT_LABELS

            dept_label = DEPARTMENT_LABELS.get(role, role.title())
            event_name = getattr(request_item, "event_name", "") or "Event"
            subject = f"Clarification needed from {dept_label}: {event_name}"
            body = (
                f"The {dept_label} team needs clarification for your event \"{event_name}\".\n\n"
                f"Message:\n{comment}\n\n"
                "Please log in to the Event Booking portal, review the feedback, "
                "and reply in the discussion thread."
            )
            requester_email = getattr(request_item, "requester_email", "")
            if requester_email:
                await send_notification_email(
                    recipient_email=requester_email,
                    subject=subject,
                    body=body,
                    requester=user,
                    fallback_role=role,
                )
        except Exception as exc:
            logger.warning("Clarification notification failed for %s: %s", role, exc)

    # Ensure a discussion thread exists for this dept+faculty pair on every decision
    if ar_id:
        try:
            from event_chat_service import ensure_approval_thread_chat, DEPARTMENT_LABELS

            dept_label = DEPARTMENT_LABELS.get(role, role.title())
            event_name = getattr(request_item, "event_name", "") or "Event"
            initial_msg = ""
            if normalized_status == "clarification_requested":
                initial_msg = comment

            await ensure_approval_thread_chat(
                approval_request_id=ar_id,
                department=role,
                faculty_user_id=request_item.requester_id,
                department_user_id=str(user.id),
                related_request_id=str(request_item.id),
                related_kind=related_kind,
                title=f"{dept_label} – {event_name}",
                initial_message=initial_msg,
                sender_name=user.name,
                sender_email=user.email or "",
            )
        except Exception as exc:
            logger.warning("Thread ensure failed for %s: %s", role, exc)

    # Close the per-dept thread when its specific request is finalized
    if normalized_status in ("approved", "rejected") and ar_id:
        try:
            from event_chat_service import close_threads_for_request
            await close_threads_for_request(
                approval_request_id=ar_id,
                department=role,
                related_request_id=str(request_item.id),
                reason=normalized_status,
            )
        except Exception as exc:
            logger.warning("close_threads_for_request failed for %s: %s", role, exc)

    return True
