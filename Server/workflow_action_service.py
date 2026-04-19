"""Persist and query structured workflow decisions (approve / reject / need clarification) with comments."""

from collections import defaultdict
from datetime import datetime
from typing import Any, Dict, List, Optional

from beanie import PydanticObjectId

from models import ApprovalRequest, User, WorkflowActionLog


async def _resolve_parent_thread(parent_id: Optional[str]) -> tuple[Optional[str], Optional[str]]:
    """Validate parent id and return (parent_id_str, thread_id for child)."""
    if not parent_id:
        return None, None
    try:
        oid = PydanticObjectId(parent_id)
    except Exception:
        return None, None
    parent = await WorkflowActionLog.get(oid)
    if not parent:
        return None, None
    tid = getattr(parent, "thread_id", None) or str(parent.id)
    return str(parent.id), tid


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
    parent_id: Optional[str] = None,
    thread_id: Optional[str] = None,
) -> WorkflowActionLog:
    v_parent, inherited_thread = await _resolve_parent_thread(parent_id)
    use_thread = thread_id or inherited_thread

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
        parent_id=v_parent,
        thread_id=use_thread,
        is_deleted=False,
    )
    await log.insert()
    if not log.parent_id and not log.thread_id:
        log.thread_id = str(log.id)
        await log.save()
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
    return await WorkflowActionLog.find({"$or": or_conditions}).sort(+WorkflowActionLog.created_at).to_list()


def filter_logs_for_approval_discussion(
    entries: List[WorkflowActionLog],
    approval_request_id: str,
) -> List[WorkflowActionLog]:
    """Subset of logs that belong to the registrar approval thread (excludes department requirement rows)."""
    aid = str(approval_request_id)
    return [
        e
        for e in entries
        if (e.approval_request_id or "") == aid
        and (e.related_kind or "") == "approval_request"
        and str(e.related_id) == aid
    ]


def nest_workflow_logs_as_trees(scoped: List[WorkflowActionLog]) -> List[Dict[str, Any]]:
    """Build nested reply trees (multiple roots, sorted by created_at)."""
    by_id = {str(e.id): e for e in scoped}
    children: Dict[str, List[WorkflowActionLog]] = defaultdict(list)
    roots: List[WorkflowActionLog] = []

    for e in scoped:
        pid = getattr(e, "parent_id", None)
        if pid and pid in by_id:
            children[pid].append(e)
        else:
            roots.append(e)

    roots.sort(key=lambda x: x.created_at)
    for k in list(children.keys()):
        children[k].sort(key=lambda x: x.created_at)

    def to_node(entry: WorkflowActionLog) -> Dict[str, Any]:
        eid = str(entry.id)
        deleted = bool(getattr(entry, "is_deleted", False))
        text = "[Deleted]" if deleted else (entry.comment or "")
        return {
            "id": eid,
            "event_id": entry.event_id,
            "approval_request_id": entry.approval_request_id,
            "related_kind": entry.related_kind,
            "related_id": entry.related_id,
            "role": entry.role,
            "action_type": entry.action_type,
            "comment": text,
            "action_by": entry.action_by,
            "action_by_user_id": entry.action_by_user_id,
            "created_at": entry.created_at,
            "parent_id": getattr(entry, "parent_id", None),
            "thread_id": getattr(entry, "thread_id", None),
            "is_deleted": deleted,
            "replies": [to_node(c) for c in children.get(eid, [])],
        }

    return [to_node(r) for r in roots]


async def record_approval_discussion_reply(
    *,
    approval: ApprovalRequest,
    user: User,
    parent_id: str,
    message: str,
) -> WorkflowActionLog:
    """Append a threaded reply on the registrar approval discussion."""
    if str(approval.requester_id) == str(user.id):
        role = "requester"
    else:
        ur = (user.role or "").strip().lower()
        role = ur if ur in ("registrar", "vice_chancellor", "deputy_registrar", "finance_team") else "registrar"
    return await record_workflow_action(
        event_id=approval.event_id,
        approval_request_id=str(approval.id),
        related_kind="approval_request",
        related_id=str(approval.id),
        role=role,
        action_type="reply",
        comment=message.strip(),
        action_by_email=user.email or "",
        action_by_user_id=str(user.id),
        parent_id=parent_id,
    )
