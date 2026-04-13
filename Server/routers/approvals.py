import base64
import logging
import os
import re
from datetime import datetime, timezone
from typing import Optional

from beanie import PydanticObjectId
from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, UploadFile, status
import requests

from auth import ensure_google_access_token, get_primary_email_by_role, is_admin_email
from drive import upload_report_file
from idempotency import get_cached_response, get_idempotency_key, store_response
from models import (
    ApprovalRequest, ChatConversation, ChatMessage, Event,
    FacilityManagerRequest, ItRequest, MarketingRequest, TransportRequest,
    User, WorkflowActionLog,
)
from event_status import combine_datetime, compute_event_status, event_has_started
from event_chat_service import (
    DEPARTMENT_LABELS,
    ensure_approval_thread_chat,
    list_approval_threads,
    resolve_approval_thread_status,
)
from rate_limit import limiter
from routers.admin import serialize_approval
from routers.deps import get_current_user
from routers.events import (
    get_expected_budget_breakdown_filename,
    serialize_workflow_log_entry,
    sync_event_to_google_calendar,
)
from decision_helpers import action_type_for_status, parse_registrar_decision_status, registrar_decision_comment
from schemas import (
    ApprovalDecision, ApprovalDiscussionReply, ApprovalRequestResponse,
    ApprovalThreadEnsureRequest, ApprovalThreadInfo, ApprovalThreadMessage,
    ApprovalThreadParticipant, PaginatedResponse, WorkflowActionLogEntry,
)
from workflow_action_service import record_approval_discussion_reply, record_workflow_action

router = APIRouter(prefix="/approvals", tags=["Approvals"])
logger = logging.getLogger("event-booking.approvals")


def _build_raw_email(to_email: str, subject: str, body: str) -> str:
    headers = [
        f"To: {to_email}",
        f"Subject: {subject}",
        "Content-Type: text/plain; charset=\"UTF-8\"",
    ]
    return "\r\n".join(headers) + "\r\n\r\n" + body


async def notify_requester_on_clarification(
    approver: User,
    requester_email: str,
    event_name: str,
    comment: str,
) -> None:
    """Email requester when registrar requests clarification (pause + feedback)."""
    try:
        access_token = await ensure_google_access_token(approver)
    except HTTPException:
        logger.warning("Cannot notify requester: approver Google token not available")
        return
    subject = f"Clarification needed: {event_name}"
    body = (
        f"The registrar needs clarification before approving your event \"{event_name}\".\n\n"
        f"Message:\n{comment}\n\n"
        "Please log in to the Event Booking portal, review the feedback, update your request if needed, "
        "and ensure your budget breakdown PDF is uploaded if required."
    )
    raw_message = _build_raw_email(requester_email, subject, body)
    encoded_message = base64.urlsafe_b64encode(raw_message.encode("utf-8")).decode("utf-8")
    response = requests.post(
        "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"raw": encoded_message},
        timeout=15,
    )
    if response.status_code not in {200, 202}:
        logger.warning("Failed to notify requester of clarification: %s", response.text)


async def notify_requester_on_approval(
    approver: User,
    requester_email: str,
    event_name: str,
    event_id: str,
) -> None:
    """Send email to requester when registrar approves their event."""
    try:
        access_token = await ensure_google_access_token(approver)
    except HTTPException:
        logger.warning("Cannot notify requester: approver Google token not available")
        return
    subject = f"Event Approved: {event_name}"
    body = (
        f"Your event \"{event_name}\" has been approved by the registrar.\n\n"
        "The event is now active. Please log in to the Event Booking portal and "
        "submit your requirements to the Facility Manager, IT, and Marketing teams."
    )
    raw_message = _build_raw_email(requester_email, subject, body)
    encoded_message = base64.urlsafe_b64encode(raw_message.encode("utf-8")).decode("utf-8")
    response = requests.post(
        "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"raw": encoded_message},
        timeout=15,
    )
    if response.status_code not in {200, 202}:
        logger.warning("Failed to notify requester of approval: %s", response.text)


def normalize_time(value: str | None) -> str:
    if not value:
        return ""
    parts = value.split(":")
    return ":".join(parts[:2])


DEFAULT_LIMIT = 50
MAX_LIMIT = 100


@router.get("/me", response_model=PaginatedResponse[ApprovalRequestResponse])
async def list_my_requests(
    user: User = Depends(get_current_user),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
):
    query = ApprovalRequest.find(ApprovalRequest.requester_id == str(user.id)).sort("-created_at")
    total = await query.count()
    requests = await query.skip(offset).limit(limit).to_list()
    next_offset = offset + limit if offset + limit < total else None
    return PaginatedResponse[ApprovalRequestResponse](
        items=[serialize_approval(item) for item in requests],
        total=total,
        limit=limit,
        offset=offset,
        next_offset=next_offset,
    )


@router.get("/inbox", response_model=PaginatedResponse[ApprovalRequestResponse])
async def list_inbox(
    user: User = Depends(get_current_user),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
):
    role = (user.role or "").strip().lower()
    if role == "vice_chancellor":
        email = (await get_primary_email_by_role("vice_chancellor") or "").strip()
    else:
        email = (user.email or "").strip()
    if not email:
        return PaginatedResponse[ApprovalRequestResponse](
            items=[],
            total=0,
            limit=limit,
            offset=offset,
            next_offset=None,
        )
    regex = re.compile(f"^{re.escape(email)}$", re.IGNORECASE)
    query = ApprovalRequest.find({"requested_to": {"$regex": regex}}).sort("-created_at")
    total = await query.count()
    requests = await query.skip(offset).limit(limit).to_list()
    next_offset = offset + limit if offset + limit < total else None
    return PaginatedResponse[ApprovalRequestResponse](
        items=[serialize_approval(item) for item in requests],
        total=total,
        limit=limit,
        offset=offset,
        next_offset=next_offset,
    )


@router.post("/{request_id}/budget-breakdown", response_model=ApprovalRequestResponse)
@limiter.limit("30/minute")
async def upload_budget_breakdown(
    request: Request,
    request_id: str,
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
):
    """Upload PDF budget breakdown to Drive; stored on the pending approval until the event is created."""
    approval = await ApprovalRequest.get(request_id)
    if not approval:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")
    if approval.requester_id != str(user.id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed")
    if approval.status not in ("pending", "clarification_requested"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Budget breakdown can only be uploaded or replaced while the request is pending or awaiting clarification",
        )

    if not file.filename or not file.filename.lower().endswith(".pdf"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only PDF files are allowed")

    contents = await file.read()
    max_size = 10 * 1024 * 1024
    if len(contents) > max_size:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="File too large (max 10MB)")

    folder_id = os.getenv("GOOGLE_DRIVE_FOLDER_ID", "")
    if not folder_id:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Google Drive folder not configured",
        )

    drive_display_name = get_expected_budget_breakdown_filename(approval.event_name, approval.start_date)
    try:
        access_token = await ensure_google_access_token(user)
        drive_file = upload_report_file(
            access_token=access_token,
            file_name=drive_display_name,
            file_bytes=contents,
            mime_type="application/pdf",
            folder_id=folder_id,
            replace_file_id=getattr(approval, "budget_breakdown_file_id", None),
        )
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Unable to upload file: {exc}",
        )

    approval.budget_breakdown_file_id = drive_file.get("id")
    approval.budget_breakdown_file_name = drive_file.get("name")
    approval.budget_breakdown_web_view_link = drive_file.get("webViewLink")
    approval.budget_breakdown_uploaded_at = datetime.utcnow()
    await approval.save()

    return serialize_approval(approval)


@router.get("/{request_id}/threads", response_model=list[ApprovalThreadInfo])
async def get_approval_threads(
    request_id: str,
    department: Optional[str] = Query(default=None, description="Filter to a specific department thread"),
    user: User = Depends(get_current_user),
):
    """Return department-isolated approval threads visible to the current user.

    Visibility rules (strict conversation isolation):
    - Faculty requester: sees only threads where they are a participant.
    - Department user: sees only threads where they are a participant.
    - Admin: sees all threads for oversight.
    - Registrar: sees only threads where they are a participant (registrar
      threads) — NOT other department threads unless explicitly added.
    """
    try:
        oid = PydanticObjectId(request_id)
    except Exception:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")
    approval = await ApprovalRequest.get(oid)
    if not approval:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")

    role = (user.role or "").strip().lower()
    uid = str(user.id)
    is_admin = role == "admin" or is_admin_email(user.email or "")
    is_vc = role == "vice_chancellor"

    conversations = await list_approval_threads(str(approval.id))

    # Filter to specific department if requested
    if department:
        conversations = [c for c in conversations if c.department == department.strip().lower()]

    result: list[ApprovalThreadInfo] = []
    for conv in conversations:
        user_is_participant = uid in conv.participants

        # Strict visibility: participant or admin only
        if is_admin:
            pass  # admin oversight
        elif user_is_participant:
            pass  # direct participant
        elif is_vc and (conv.department or "").strip().lower() == "registrar":
            pass  # vice chancellor: same oversight as registrar dashboard for registrar threads
        else:
            continue  # PRIVACY: skip threads user is not part of

        participants: list[ApprovalThreadParticipant] = []
        for pid in conv.participants:
            u = await User.get(pid)
            if u:
                participants.append(ApprovalThreadParticipant(
                    id=str(u.id), name=u.name, email=u.email, role=u.role or "",
                ))

        raw_messages = await ChatMessage.find(
            {"conversation_id": str(conv.id), "is_deleted": {"$ne": True}},
        ).sort("created_at").to_list()
        messages = [
            ApprovalThreadMessage(
                id=str(m.id),
                sender_id=m.sender_id,
                sender_name=m.sender_name,
                content=m.content,
                created_at=m.created_at,
                reply_to_message_id=getattr(m, "reply_to_message_id", None),
                reply_to_snapshot=getattr(m, "reply_to_snapshot", None),
            )
            for m in raw_messages
        ]

        # Look up the dept request's current workflow status so the frontend can
        # decide whether to show action buttons (approve/reject/clarification).
        dept_request_status: Optional[str] = None
        rk = (conv.related_kind or "").lower()
        rid = conv.related_request_id
        if rid:
            try:
                oid_rid = PydanticObjectId(rid)
                if rk == "facility_request":
                    dr = await FacilityManagerRequest.get(oid_rid)
                    dept_request_status = dr.status if dr else None
                elif rk == "it_request":
                    dr = await ItRequest.get(oid_rid)
                    dept_request_status = dr.status if dr else None
                elif rk == "marketing_request":
                    dr = await MarketingRequest.get(oid_rid)
                    dept_request_status = dr.status if dr else None
                elif rk == "transport_request":
                    dr = await TransportRequest.get(oid_rid)
                    dept_request_status = dr.status if dr else None
            except Exception:
                dept_request_status = None

        result.append(ApprovalThreadInfo(
            id=str(conv.id),
            department=conv.department or "",
            department_label=DEPARTMENT_LABELS.get(conv.department or "", conv.department or ""),
            related_request_id=conv.related_request_id,
            related_kind=conv.related_kind,
            thread_status=conv.thread_status or "active",
            dept_request_status=dept_request_status,
            participants=participants,
            created_at=conv.created_at,
            messages=messages,
            closed_at=getattr(conv, "closed_at", None),
            closed_reason=getattr(conv, "closed_reason", None),
        ))
    return result


@router.post("/{request_id}/threads/ensure", response_model=ApprovalThreadInfo)
async def ensure_department_thread(
    request_id: str,
    payload: ApprovalThreadEnsureRequest,
    user: User = Depends(get_current_user),
):
    """Create or retrieve an approval discussion thread for a department.

    Faculty can initiate threads with any department.  Department users can
    initiate a thread with the faculty for their own department.  A first
    message is posted when supplied.
    """
    try:
        oid = PydanticObjectId(request_id)
    except Exception:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")
    approval = await ApprovalRequest.get(oid)
    if not approval:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")

    department = payload.department.strip().lower()
    valid_departments = ("registrar", "facility_manager", "it", "marketing", "transport", "iqac")
    if department not in valid_departments:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid department: {department}")

    uid = str(user.id)
    role = (user.role or "").strip().lower()
    is_requester = str(approval.requester_id) == uid
    is_admin_or_reg = role in ("registrar", "vice_chancellor", "admin") or is_admin_email(user.email or "")

    # Determine who the two parties are
    faculty_user_id = str(approval.requester_id)
    department_user_id: str | None = None

    if is_requester or is_admin_or_reg:
        # Faculty or registrar initiating — find department person
        if department == "registrar":
            # Find the registrar user (the one in requested_to or by role)
            reg_email = (approval.requested_to or "").strip().lower()
            dept_u = await User.find_one({"email": reg_email}) if reg_email else None
            if not dept_u:
                from auth import get_primary_email_by_role as _get_pe
                reg_email2 = await _get_pe("registrar")
                dept_u = await User.find_one({"email": reg_email2}) if reg_email2 else None
            department_user_id = str(dept_u.id) if dept_u else uid
        elif department == "iqac":
            from auth import get_primary_email_by_role as _get_pe
            iqac_email = await _get_pe("iqac")
            dept_u = await User.find_one({"email": iqac_email}) if iqac_email else None
            department_user_id = str(dept_u.id) if dept_u else uid
        else:
            # Look for an existing dept request to find requested_to
            dept_model_map = {
                "facility_manager": "FacilityManagerRequest",
                "it": "ItRequest",
                "marketing": "MarketingRequest",
                "transport": "TransportRequest",
            }
            from models import FacilityManagerRequest, ItRequest, MarketingRequest, TransportRequest
            model_cls = {"facility_manager": FacilityManagerRequest, "it": ItRequest,
                         "marketing": MarketingRequest, "transport": TransportRequest}[department]
            dept_req = None
            if approval.event_id:
                dept_req = await model_cls.find_one({"event_id": approval.event_id})
            if dept_req and dept_req.requested_to:
                dept_u = await User.find_one({"email": dept_req.requested_to.strip().lower()})
                department_user_id = str(dept_u.id) if dept_u else None
            if not department_user_id:
                from auth import get_primary_email_by_role as _get_pe
                dept_email = await _get_pe(department)
                dept_u = await User.find_one({"email": dept_email}) if dept_email else None
                department_user_id = str(dept_u.id) if dept_u else uid

    elif role == department:
        # Department user initiating — they are the dept side
        department_user_id = uid
    else:
        # Check if user is already a participant in a thread for this dept
        existing = await ChatConversation.find_one({
            "thread_kind": "approval_thread",
            "approval_request_id": str(approval.id),
            "department": department,
            "participants": uid,
        })
        if not existing:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorised for this thread")
        department_user_id = uid

    if not department_user_id:
        department_user_id = uid

    from event_chat_service import (
        DEPARTMENT_LABELS,
        build_last_message_snapshot,
        ensure_approval_thread_chat,
        increment_participant_unreads,
    )
    dept_label = DEPARTMENT_LABELS.get(department, department.title())
    conv = await ensure_approval_thread_chat(
        approval_request_id=str(approval.id),
        department=department,
        faculty_user_id=faculty_user_id,
        department_user_id=department_user_id,
        related_request_id=str(approval.id),
        related_kind="approval_request",
        title=f"{dept_label} discussion – {approval.event_name}",
        initial_message="",
        sender_name=user.name,
        sender_email=user.email or "",
    )

    # Post initial message if provided
    if payload.message and payload.message.strip():
        from datetime import datetime
        msg = ChatMessage(
            conversation_id=str(conv.id),
            sender_id=uid,
            sender_name=user.name,
            sender_email=user.email or "",
            content=payload.message.strip(),
            read_by=[uid],
            created_at=datetime.utcnow(),
        )
        await msg.insert()
        conv.last_message = build_last_message_snapshot(msg)
        conv.updated_at = datetime.utcnow()
        await conv.save()
        await increment_participant_unreads(conv, uid)
        try:
            from event_chat_service import notify_thread_reply
            await notify_thread_reply(conv, msg, user, approval)
        except Exception as exc:
            logger.warning("ensure_department_thread notify failed: %s", exc)

    # Serialize and return
    participants: list[ApprovalThreadParticipant] = []
    for pid in conv.participants:
        pu = await User.get(pid)
        if pu:
            participants.append(ApprovalThreadParticipant(
                id=str(pu.id), name=pu.name, email=pu.email, role=pu.role or "",
            ))
    raw_msgs = await ChatMessage.find(
        {"conversation_id": str(conv.id), "is_deleted": {"$ne": True}},
    ).sort("created_at").to_list()
    messages = [
        ApprovalThreadMessage(
            id=str(m.id), sender_id=m.sender_id, sender_name=m.sender_name,
            content=m.content, created_at=m.created_at,
        )
        for m in raw_msgs
    ]
    return ApprovalThreadInfo(
        id=str(conv.id),
        department=conv.department or "",
        department_label=DEPARTMENT_LABELS.get(conv.department or "", conv.department or ""),
        related_request_id=conv.related_request_id,
        related_kind=conv.related_kind,
        thread_status=conv.thread_status or "active",
        participants=participants,
        created_at=conv.created_at,
        messages=messages,
        closed_at=getattr(conv, "closed_at", None),
        closed_reason=getattr(conv, "closed_reason", None),
    )


@router.post("/{request_id}/threads/{conv_id}/reopen", response_model=ApprovalThreadInfo)
async def reopen_approval_thread(
    request_id: str,
    conv_id: str,
    user: User = Depends(get_current_user),
):
    """Reopen a resolved/closed approval discussion thread.

    Restricted to registrar and admin roles.
    """
    role = (user.role or "").strip().lower()
    if role not in ("registrar", "vice_chancellor", "admin") and not is_admin_email(user.email or ""):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only registrar or admin can reopen threads")

    try:
        oid = PydanticObjectId(request_id)
    except Exception:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")
    approval = await ApprovalRequest.get(oid)
    if not approval:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")

    try:
        coid = PydanticObjectId(conv_id)
    except Exception:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Thread not found")
    conv = await ChatConversation.get(coid)
    if not conv or conv.thread_kind != "approval_thread":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Thread not found")
    if str(conv.approval_request_id) != str(approval.id):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Thread does not belong to this approval")

    conv.thread_status = "active"
    conv.closed_at = None
    conv.closed_reason = None
    await conv.save()

    # Log the reopen action for audit
    try:
        await record_workflow_action(
            event_id=approval.event_id,
            approval_request_id=str(approval.id),
            related_kind=conv.related_kind or "approval_request",
            related_id=conv.related_request_id or str(approval.id),
            role=user.role or "registrar",
            action_type="reopen",
            comment="Thread reopened",
            action_by_email=user.email or "",
            action_by_user_id=str(user.id),
        )
    except Exception as exc:
        logger.warning("reopen_approval_thread: audit log failed: %s", exc)

    participants: list[ApprovalThreadParticipant] = []
    for pid in conv.participants:
        pu = await User.get(pid)
        if pu:
            participants.append(ApprovalThreadParticipant(
                id=str(pu.id), name=pu.name, email=pu.email, role=pu.role or "",
            ))
    raw_msgs = await ChatMessage.find(
        {"conversation_id": str(conv.id), "is_deleted": {"$ne": True}},
    ).sort("created_at").to_list()
    messages = [
        ApprovalThreadMessage(
            id=str(m.id), sender_id=m.sender_id, sender_name=m.sender_name,
            content=m.content, created_at=m.created_at,
            reply_to_message_id=getattr(m, "reply_to_message_id", None),
            reply_to_snapshot=getattr(m, "reply_to_snapshot", None),
        )
        for m in raw_msgs
    ]
    return ApprovalThreadInfo(
        id=str(conv.id),
        department=conv.department or "",
        department_label=DEPARTMENT_LABELS.get(conv.department or "", conv.department or ""),
        related_request_id=conv.related_request_id,
        related_kind=conv.related_kind,
        thread_status="active",
        participants=participants,
        created_at=conv.created_at,
        messages=messages,
        closed_at=None,
        closed_reason=None,
    )


@router.post("/{request_id}/reply", response_model=WorkflowActionLogEntry)
async def post_approval_discussion_reply(
    request_id: str,
    payload: ApprovalDiscussionReply,
    user: User = Depends(get_current_user),
):
    """Reply on approval discussion via department thread (thread_id) or legacy parent (parent_id).

    Thread-based replies are allowed at any approval status (approved, rejected, etc.) as long
    as the specific thread is not resolved.  Only the legacy parent_id path is gated by status.
    """
    try:
        oid = PydanticObjectId(request_id)
    except Exception:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")
    approval = await ApprovalRequest.get(oid)
    if not approval:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")

    # ---- Thread-based reply (department chat) ----
    if payload.thread_id:
        conv = await ChatConversation.find_one({"_id": PydanticObjectId(payload.thread_id)})
        if not conv or conv.thread_kind != "approval_thread":
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Thread not found")
        if str(conv.approval_request_id) != str(approval.id):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Thread does not belong to this approval")
        if str(user.id) not in conv.participants:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not a participant of this thread")
        if (conv.thread_status or "active") in ("resolved", "closed"):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="This thread has been resolved or closed")

        from event_chat_service import (
            build_last_message_snapshot,
            increment_participant_unreads,
            notify_thread_reply,
        )

        reply_snapshot: dict | None = None
        if payload.reply_to_message_id:
            try:
                orig = await ChatMessage.get(PydanticObjectId(payload.reply_to_message_id))
                if orig and not orig.is_deleted:
                    reply_snapshot = {
                        "message_id": str(orig.id),
                        "sender_name": orig.sender_name,
                        "content_preview": (orig.content or "")[:200],
                    }
            except Exception:
                pass

        msg = ChatMessage(
            conversation_id=str(conv.id),
            sender_id=str(user.id),
            sender_name=user.name,
            sender_email=user.email or "",
            content=payload.message.strip(),
            read_by=[str(user.id)],
            created_at=datetime.utcnow(),
            reply_to_message_id=payload.reply_to_message_id or None,
            reply_to_snapshot=reply_snapshot,
        )
        await msg.insert()
        conv.last_message = build_last_message_snapshot(msg)
        conv.updated_at = datetime.utcnow()

        is_reply_from_requester = str(user.id) == str(approval.requester_id)

        # Per-thread discussion turn
        conv.thread_status = "waiting_for_department" if is_reply_from_requester else "waiting_for_faculty"
        await conv.save()
        await increment_participant_unreads(conv, str(user.id))

        # Global discussion_status on the approval (backward compat)
        approval.discussion_status = conv.thread_status
        await approval.save()

        # Email notification to the other participant(s)
        try:
            await notify_thread_reply(conv, msg, user, approval)
        except Exception as exc:
            logger.warning("Thread reply notification failed: %s", exc)

        log = await record_workflow_action(
            event_id=approval.event_id,
            action_type="discussion_reply",
            approval_request_id=str(approval.id),
            related_kind=conv.related_kind or "approval_request",
            related_id=conv.related_request_id or str(approval.id),
            role=user.role or "faculty",
            comment=payload.message.strip(),
            action_by_email=user.email or "",
            action_by_user_id=str(user.id),
            thread_id=payload.thread_id,
        )
        return serialize_workflow_log_entry(log)

    # ---- Legacy parent_id reply (registrar discussion) ----
    if not payload.parent_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Either thread_id or parent_id must be provided.",
        )

    # Legacy path is only valid when approval is still open
    if approval.status in ("approved", "rejected"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This approval is closed for further discussion.",
        )
    if approval.status not in ("pending", "clarification_requested"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot add a reply in the current approval state.",
        )

    role = (user.role or "").strip().lower()
    is_requester = str(approval.requester_id) == str(user.id)
    approver_email = (approval.requested_to or "").strip().lower()
    user_email = (user.email or "").strip().lower()
    is_assigned_approver = bool(approver_email and approver_email == user_email)
    is_privileged = role in ("registrar", "vice_chancellor", "admin") or is_admin_email(user.email or "")

    if not (is_requester or is_assigned_approver or is_privileged):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed")

    try:
        parent_oid = PydanticObjectId(payload.parent_id)
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid parent_id")
    parent = await WorkflowActionLog.get(parent_oid)
    if not parent:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Parent comment not found")
    if str(parent.approval_request_id or "") != str(approval.id) or parent.related_kind != "approval_request":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Parent does not belong to this approval.",
        )

    log = await record_approval_discussion_reply(
        approval=approval,
        user=user,
        parent_id=str(parent.id),
        message=payload.message.strip(),
    )

    is_reply_from_requester = str(user.id) == str(approval.requester_id)
    approval.discussion_status = "waiting_for_department" if is_reply_from_requester else "waiting_for_faculty"
    await approval.save()

    # Email notification: notify the "other side" of the registrar discussion
    try:
        from event_chat_service import notify_legacy_discussion_reply
        await notify_legacy_discussion_reply(user, approval, payload.message.strip())
    except Exception as exc:
        logger.warning("Legacy discussion reply notification failed: %s", exc)

    return serialize_workflow_log_entry(log)


@router.patch("/{request_id}", response_model=ApprovalRequestResponse)
async def decide_request(
    request: Request,
    request_id: str,
    payload: ApprovalDecision,
    user: User = Depends(get_current_user),
):
    idem_key = get_idempotency_key(request)
    if idem_key:
        cached = await get_cached_response(idem_key)
        if cached:
            from fastapi.responses import JSONResponse
            return JSONResponse(status_code=cached[0], content=cached[1])

    normalized_status = parse_registrar_decision_status(payload.status)
    comment = registrar_decision_comment(normalized_status, payload.comment)

    approval = await ApprovalRequest.get(request_id)
    if not approval:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")

    if event_has_started(approval.start_date, approval.start_time):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Event has already started; approval or rejection is no longer allowed.",
        )

    approver_email = (user.email or "").strip().lower()
    requested_to = (approval.requested_to or "").strip().lower()
    role_normalized = (user.role or "").strip().lower()
    if not (requested_to and approver_email == requested_to):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed")

    if approval.status in ("approved", "rejected"):
        response_body = serialize_approval(approval)
        if idem_key:
            await store_response(idem_key, 200, response_body.model_dump(mode="json"))
        return response_body

    if approval.status not in ("pending", "clarification_requested"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This approval request is no longer actionable.",
        )

    audit_role = role_normalized if role_normalized in ("registrar", "vice_chancellor") else "registrar"
    ar_log_kwargs = dict(
        approval_request_id=str(approval.id),
        related_kind="approval_request",
        related_id=str(approval.id),
        role=audit_role,
        comment=comment,
        action_by_email=user.email or "",
        action_by_user_id=str(user.id),
    )

    if normalized_status == "clarification_requested":
        approval.status = "clarification_requested"
        approval.discussion_status = "waiting_for_faculty"
        approval.decided_by = user.email
        approval.decided_at = datetime.utcnow()
        await approval.save()
        await record_workflow_action(
            event_id=approval.event_id,
            action_type=action_type_for_status(normalized_status),
            **ar_log_kwargs,
        )
        requester = await User.get(approval.requester_id)
        if requester and requester.email:
            try:
                await notify_requester_on_clarification(
                    user, requester.email, approval.event_name, comment
                )
            except Exception as exc:
                logger.warning("Requester clarification notification failed: %s", exc)
            # Auto-create an approval thread between registrar and requester
            try:
                await ensure_approval_thread_chat(
                    approval_request_id=str(approval.id),
                    department="registrar",
                    faculty_user_id=str(approval.requester_id),
                    department_user_id=str(user.id),
                    related_request_id=str(approval.id),
                    related_kind="approval_request",
                    title=f"Registrar clarification – {approval.event_name}",
                    initial_message=comment,
                    sender_name=user.name,
                    sender_email=user.email or "",
                )
            except Exception as exc:
                logger.warning("Approval thread creation failed: %s", exc)
    elif normalized_status == "rejected":
        approval.status = "rejected"
        approval.discussion_status = None
        approval.decided_by = user.email
        approval.decided_at = datetime.utcnow()
        await approval.save()
        await record_workflow_action(
            event_id=approval.event_id,
            action_type=action_type_for_status(normalized_status),
            **ar_log_kwargs,
        )
    elif normalized_status == "approved":
        if not getattr(approval, "budget_breakdown_file_id", None):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="A budget breakdown PDF must be uploaded before this request can be approved.",
            )
        if not approval.event_id:
            start_dt = combine_datetime(approval.start_date, approval.start_time)
            end_dt = combine_datetime(approval.end_date, approval.end_time)
            if end_dt < start_dt:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="End datetime must be after start datetime",
                )
            if not getattr(approval, "override_conflict", False):
                existing_events = await Event.find_all().to_list()
                for existing in existing_events:
                    existing_start = combine_datetime(existing.start_date, existing.start_time)
                    existing_end = combine_datetime(existing.end_date, existing.end_time)
                    if start_dt < existing_end and end_dt > existing_start and existing.venue_name == approval.venue_name:
                        raise HTTPException(
                            status_code=status.HTTP_409_CONFLICT,
                            detail="Schedule conflict detected for the venue",
                        )
            event = Event(
                name=approval.event_name,
                facilitator=approval.facilitator,
                description=approval.description,
                venue_name=approval.venue_name,
                intendedAudience=getattr(approval, "intendedAudience", None),
                budget=getattr(approval, "budget", None),
                budget_breakdown_file_id=getattr(approval, "budget_breakdown_file_id", None),
                budget_breakdown_file_name=getattr(approval, "budget_breakdown_file_name", None),
                budget_breakdown_web_view_link=getattr(approval, "budget_breakdown_web_view_link", None),
                budget_breakdown_uploaded_at=getattr(approval, "budget_breakdown_uploaded_at", None),
                start_date=approval.start_date,
                start_time=approval.start_time,
                end_date=approval.end_date,
                end_time=approval.end_time,
                created_by=approval.requester_id,
                status=compute_event_status(start_dt, end_dt),
            )
            await event.insert()
            requester = await User.get(approval.requester_id)
            if not requester:
                await event.delete()
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Requester not found")
            try:
                await sync_event_to_google_calendar(event, requester)
            except (HTTPException, Exception) as exc:
                logger.warning(
                    "Google Calendar sync skipped for approved event %s: %s",
                    event.name,
                    exc,
                )

            approval.event_id = str(event.id)
            matching_query = {
                "requester_id": approval.requester_id,
                "event_name": approval.event_name,
                "start_date": approval.start_date,
                "end_date": approval.end_date,
                "event_id": None,
            }
            approval_start = normalize_time(approval.start_time)
            approval_end = normalize_time(approval.end_time)

            facility_requests = await FacilityManagerRequest.find(matching_query).to_list()
            for request_item in facility_requests:
                if (
                    normalize_time(request_item.start_time) == approval_start
                    and normalize_time(request_item.end_time) == approval_end
                ):
                    request_item.event_id = approval.event_id
                    await request_item.save()

            marketing_requests = await MarketingRequest.find(matching_query).to_list()
            for request_item in marketing_requests:
                if (
                    normalize_time(request_item.start_time) == approval_start
                    and normalize_time(request_item.end_time) == approval_end
                ):
                    request_item.event_id = approval.event_id
                    await request_item.save()

            it_requests = await ItRequest.find(matching_query).to_list()
            for request_item in it_requests:
                if (
                    normalize_time(request_item.start_time) == approval_start
                    and normalize_time(request_item.end_time) == approval_end
                ):
                    request_item.event_id = approval.event_id
                    await request_item.save()

            transport_requests = await TransportRequest.find(matching_query).to_list()
            for request_item in transport_requests:
                if (
                    normalize_time(request_item.start_time) == approval_start
                    and normalize_time(request_item.end_time) == approval_end
                ):
                    request_item.event_id = approval.event_id
                    await request_item.save()

            try:
                await notify_requester_on_approval(user, requester.email, event.name, str(event.id))
            except Exception as exc:
                logger.warning("Requester approval notification failed: %s", exc)

            try:
                from event_chat_service import ensure_event_group_chat

                await ensure_event_group_chat(
                    str(event.id),
                    event.name,
                    approval.requester_id,
                    str(user.id),
                )
            except Exception as exc:
                logger.warning("Event group chat creation failed: %s", exc)

        approval.status = "approved"
        approval.discussion_status = None
        approval.decided_by = user.email
        approval.decided_at = datetime.utcnow()
        await approval.save()
        await record_workflow_action(
            event_id=approval.event_id,
            action_type=action_type_for_status(normalized_status),
            **ar_log_kwargs,
        )

    response_body = serialize_approval(approval)

    # Resolve all approval threads when the decision is final
    if normalized_status in ("approved", "rejected"):
        try:
            await resolve_approval_thread_status(str(approval.id), normalized_status)
        except Exception as exc:
            logger.warning("Resolve approval threads failed: %s", exc)

    if idem_key:
        await store_response(idem_key, 200, response_body.model_dump(mode="json"))
    return response_body
