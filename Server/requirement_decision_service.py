"""Apply department requirement decisions with workflow logging."""

from datetime import datetime
from typing import Union

from models import ApprovalRequest, FacilityManagerRequest, ItRequest, MarketingRequest, TransportRequest, User
from decision_helpers import action_type_for_status
from workflow_action_service import record_workflow_action

RequirementDoc = Union[FacilityManagerRequest, ItRequest, MarketingRequest, TransportRequest]


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
    return True
