"""Persist and query structured workflow decisions (approve / reject / clarification) with comments."""

from datetime import datetime
from typing import List, Optional

from models import WorkflowActionLog


async def record_workflow_action(
    *,
    event_id: Optional[str],
    approval_request_id: Optional[str],
    related_kind: str,
    related_id: str,
    role: str,
    action_type: str,
    comment: str,
    action_by_email: str,
    action_by_user_id: str,
) -> WorkflowActionLog:
    log = WorkflowActionLog(
        event_id=event_id,
        approval_request_id=approval_request_id,
        related_kind=related_kind,
        related_id=related_id,
        role=role,
        action_type=action_type,
        comment=comment,
        action_by=action_by_email,
        action_by_user_id=action_by_user_id,
        created_at=datetime.utcnow(),
    )
    await log.insert()
    return log


async def list_workflow_actions_for_scope(
    *,
    event_id: Optional[str] = None,
    approval_request_id: Optional[str] = None,
) -> List[WorkflowActionLog]:
    """Logs for an event id and/or a registrar approval id (pre-event clarifications use approval id only)."""
    or_conditions = []
    if event_id:
        or_conditions.append({"event_id": event_id})
    if approval_request_id:
        or_conditions.append({"approval_request_id": approval_request_id})
    if not or_conditions:
        return []
    return await WorkflowActionLog.find({"$or": or_conditions}).sort(-WorkflowActionLog.created_at).to_list()
