import base64
import logging
import os
import re
import traceback
from datetime import datetime, timezone
from typing import Optional

from beanie import PydanticObjectId
from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, UploadFile, status
import requests

from auth import ensure_google_access_token, get_primary_email_by_role, is_admin_email
from drive import sanitize_folder_name, upload_file_to_nested_folder, upload_report_file
from idempotency import get_cached_response, get_idempotency_key, store_response
from upload_validation import MAX_PDF_UPLOAD_BYTES, PDF_SIZE_ERROR_DETAIL
from models import (
    ApprovalRequest, ChatConversation, ChatMessage, Event,
    FacilityManagerRequest, ItRequest, MarketingRequest, TransportRequest,
    User, WorkflowActionLog,
)
from event_status import combine_datetime, compute_event_status, event_has_started
from event_chat_service import (
    DEPARTMENT_LABELS,
    dept_key_for_stage,
    ensure_approval_thread_chat,
    list_approval_threads,
    resolve_approval_thread_status,
)
from rate_limit import limiter
from routers.admin import serialize_approval
from routers.deps import get_current_user
from routers.events import (
    BUDGET_VC_PRIMARY_THRESHOLD,
    get_expected_budget_breakdown_filename,
    notify_registrar_for_approval,
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


def effective_pipeline_stage(approval: ApprovalRequest) -> str:
    """Logical stage for routing. Legacy rows omit pipeline_stage → registrar-only final gate."""
    ps = (getattr(approval, "pipeline_stage", None) or "").strip().lower()
    if ps:
        return ps
    if (getattr(approval, "status", None) or "") == "approved" and getattr(approval, "event_id", None):
        return "complete"
    return "registrar"


async def user_may_act_on_approval_request(user: User, approval: ApprovalRequest) -> bool:
    """True if the user may approve/reject/clarify (assigned approver or role-matched delegate)."""
    approver_email = (user.email or "").strip().lower()
    requested_to = (approval.requested_to or "").strip().lower()
    role = (user.role or "").strip().lower()
    ps = effective_pipeline_stage(approval)

    if ps in ("after_deputy", "after_finance"):
        return False
    if not requested_to:
        return False
    if approver_email == requested_to:
        return True

    reg_primary = (await get_primary_email_by_role("registrar") or "").strip().lower()
    dep_primary = (await get_primary_email_by_role("deputy_registrar") or "").strip().lower()
    fin_primary = (await get_primary_email_by_role("finance_team") or "").strip().lower()

    if role == "deputy_registrar" and dep_primary and requested_to == dep_primary:
        return True
    if role == "finance_team" and fin_primary and requested_to == fin_primary:
        return True
    # Legacy: delegate could act on the final registrar queue
    if role == "deputy_registrar" and reg_primary and requested_to == reg_primary and ps == "registrar":
        return True
    if role == "finance_team" and reg_primary and requested_to == reg_primary and ps == "registrar":
        return True
    return False


async def notify_requester_text(
    sender: User,
    requester_email: str,
    subject: str,
    body: str,
) -> None:
    try:
        access_token = await ensure_google_access_token(sender)
    except HTTPException:
        logger.warning("Cannot email requester: sender Google token not available")
        return
    raw_message = _build_raw_email(requester_email, subject, body)
    encoded_message = base64.urlsafe_b64encode(raw_message.encode("utf-8")).decode("utf-8")
    response = requests.post(
        "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"raw": encoded_message},
        timeout=15,
    )
    if response.status_code not in {200, 202}:
        logger.warning("Failed to notify requester: %s", response.text)


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
    elif role == "deputy_registrar":
        email = (await get_primary_email_by_role("deputy_registrar") or "").strip()
    elif role == "finance_team":
        email = (await get_primary_email_by_role("finance_team") or "").strip()
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

    # Build query: active items (requested_to == email) PLUS historical items
    # where this user was the deputy or finance approver for stage-history visibility.
    active_filter = {"requested_to": {"$regex": regex}}

    history_filters = []
    if role == "deputy_registrar":
        history_filters.append({"deputy_decided_by": {"$regex": regex}})
    elif role == "finance_team":
        history_filters.append({"finance_decided_by": {"$regex": regex}})
    elif role in ("registrar", "vice_chancellor"):
        # Registrar / VC also see items they've finally decided (status approved/rejected with decided_by)
        history_filters.append({"deputy_decided_by": {"$regex": regex}})
        history_filters.append({"finance_decided_by": {"$regex": regex}})

    if history_filters:
        combined_filter = {"$or": [active_filter] + history_filters}
    else:
        combined_filter = active_filter

    query = ApprovalRequest.find(combined_filter).sort("-created_at")
    total = await query.count()
    requests = await query.skip(offset).limit(limit).to_list()
    next_offset = offset + limit if offset + limit < total else None

    # Mark each item as actionable or read-only history
    items = []
    for item in requests:
        requested_to_lower = (item.requested_to or "").strip().lower()
        email_lower = email.lower()
        is_active = bool(requested_to_lower and requested_to_lower == email_lower)
        st = (item.status or "").strip().lower()
        actionable = is_active and st in ("pending", "clarification_requested")
        items.append(serialize_approval(item, is_actionable=actionable))

    return PaginatedResponse[ApprovalRequestResponse](
        items=items,
        total=total,
        limit=limit,
        offset=offset,
        next_offset=next_offset,
    )


@router.post("/{request_id}/forward-to-finance", response_model=ApprovalRequestResponse)
async def forward_to_finance(request_id: str, user: User = Depends(get_current_user)):
    approval = await ApprovalRequest.get(request_id)
    if not approval:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")
    if str(approval.requester_id) != str(user.id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed")
    if effective_pipeline_stage(approval) != "after_deputy":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This request is not waiting to be sent to the finance department.",
        )
    finance_email = (await get_primary_email_by_role("finance_team") or "").strip()
    if not finance_email:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Finance Team email is not configured",
        )
    approval.pipeline_stage = "finance"
    approval.requested_to = finance_email
    await approval.save()
    try:
        await notify_registrar_for_approval(user, finance_email, approval, cc_emails=[])
    except Exception as exc:
        logger.warning("forward_to_finance: notification failed: %s", exc)
    return serialize_approval(approval)


@router.post("/{request_id}/forward-to-registrar", response_model=ApprovalRequestResponse)
async def forward_to_registrar(request_id: str, user: User = Depends(get_current_user)):
    approval = await ApprovalRequest.get(request_id)
    if not approval:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")
    if str(approval.requester_id) != str(user.id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed")
    if effective_pipeline_stage(approval) != "after_finance":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This request is not waiting to be sent to the Registrar.",
        )
    budget_amount = float(getattr(approval, "budget", None) or 0) or 0.0
    registrar_email = (await get_primary_email_by_role("registrar") or "").strip()
    vc_email = (await get_primary_email_by_role("vice_chancellor") or "").strip()
    if budget_amount > BUDGET_VC_PRIMARY_THRESHOLD:
        if not vc_email:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Vice Chancellor email is not configured (required for events over Rs 30,000).",
            )
        primary = vc_email
        cc_list = [registrar_email] if registrar_email else []
    else:
        if not registrar_email:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Registrar email is not configured",
            )
        primary = registrar_email
        cc_list = [vc_email] if vc_email else []
    approval.pipeline_stage = "registrar"
    approval.requested_to = primary
    approval.approval_cc = cc_list
    await approval.save()
    try:
        await notify_registrar_for_approval(user, primary, approval, cc_emails=cc_list)
    except Exception as exc:
        logger.warning("forward_to_registrar: notification failed: %s", exc)
    return serialize_approval(approval)


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
    if len(contents) > MAX_PDF_UPLOAD_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=PDF_SIZE_ERROR_DETAIL,
        )

    folder_id = os.getenv("GOOGLE_DRIVE_FOLDER_ID", "")
    if not folder_id:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Google Drive folder not configured",
        )

    drive_display_name = get_expected_budget_breakdown_filename(approval.event_name, approval.start_date)

    # Build nested folder path: Event-Uploads / YYYY / YYYY-MM / Event_Name
    try:
        _adt = datetime.strptime((approval.start_date or "")[:10], "%Y-%m-%d")
        _approval_year_s, _approval_month_s = _adt.strftime("%Y"), _adt.strftime("%Y-%m")
    except Exception:
        _approval_year_s = datetime.utcnow().strftime("%Y")
        _approval_month_s = datetime.utcnow().strftime("%Y-%m")
    _approval_folder_parts = [
        "Event-Uploads",
        _approval_year_s,
        _approval_month_s,
        sanitize_folder_name(approval.event_name),
    ]

    # Resolve a Google OAuth access token for Drive upload.
    # Priority: requesting user → any admin user with OAuth connected.
    # Service accounts cannot upload to personal My Drive (no storage quota),
    # so a real user token is always needed.
    access_token = ""
    try:
        access_token = await ensure_google_access_token(user)
        logger.info("upload_budget_breakdown: using requesting user OAuth token for request %s", request_id)
    except HTTPException as exc:
        logger.warning(
            "upload_budget_breakdown: requesting user OAuth unavailable (status=%d detail=%r) — "
            "trying admin user fallback",
            exc.status_code,
            exc.detail,
        )

    if not access_token:
        # Fall back to any admin/organizer user who has Google OAuth connected.
        # This covers IQAC/staff users who have never gone through Google OAuth flow.
        try:
            admin_candidates = await User.find(
                User.google_refresh_token != None  # noqa: E711
            ).to_list()
            for candidate in admin_candidates:
                c_role = (candidate.role or "").strip().lower()
                if c_role not in ("admin", "registrar") and not is_admin_email(candidate.email or ""):
                    continue
                try:
                    access_token = await ensure_google_access_token(candidate)
                    logger.info(
                        "upload_budget_breakdown: using admin fallback OAuth token from %s for request %s",
                        candidate.email,
                        request_id,
                    )
                    break
                except Exception:
                    continue
        except Exception:
            logger.warning(
                "upload_budget_breakdown: admin token fallback lookup failed:\n%s",
                traceback.format_exc(),
            )

    if not access_token:
        logger.error(
            "upload_budget_breakdown: no usable Google OAuth token found for request %s. "
            "Please ensure at least one admin user has connected Google OAuth.",
            request_id,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=(
                "Google Drive upload is unavailable: no connected Google account found. "
                "Please connect a Google account via Settings and try again."
            ),
        )

    try:
        drive_file = upload_file_to_nested_folder(
            access_token=access_token,
            file_name=drive_display_name,
            file_bytes=contents,
            mime_type="application/pdf",
            root_folder_id=folder_id,
            folder_path_parts=_approval_folder_parts,
            replace_file_id=getattr(approval, "budget_breakdown_file_id", None),
        )
    except HTTPException:
        # Propagate auth/permission errors with their original status codes.
        raise
    except RuntimeError as exc:
        logger.error(
            "upload_budget_breakdown: RuntimeError for request %s: %s\n%s",
            request_id, exc, traceback.format_exc(),
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )
    except Exception as exc:
        logger.error(
            "upload_budget_breakdown: unexpected error for request %s: %s\n%s",
            request_id, exc, traceback.format_exc(),
        )
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
    - Department/stage user: sees only threads where they are a participant.
    - Admin: sees all threads for oversight.
    - VC: sees registrar-stage threads for oversight (VC acts as final approver
      for high-budget events) plus any thread they are a participant of.
    Each pipeline stage (deputy, finance, registrar) stores its clarification
    thread under a distinct department key so threads are NEVER shared across
    stages, even for the same approval request.
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

        # Strict visibility: participant or admin only.
        # NOTE: No role-based cross-stage bypass is allowed here.  Each stage
        # (deputy_registrar, finance_team, registrar) uses a distinct department
        # key so a participant check alone enforces complete isolation.
        if is_admin:
            pass  # admin oversight: see all threads
        elif user_is_participant:
            pass  # direct participant
        elif is_vc and (conv.department or "").strip().lower() == "registrar":
            pass  # VC: oversight on registrar-stage threads (VC can be the final approver)
        else:
            continue  # PRIVACY: skip threads this user is not a party to

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
    valid_departments = (
        "registrar", "deputy_registrar", "finance_team",
        "facility_manager", "it", "marketing", "transport", "iqac",
    )
    if department not in valid_departments:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid department: {department}")

    uid = str(user.id)
    role = (user.role or "").strip().lower()
    is_requester = str(approval.requester_id) == uid
    is_admin_or_reg = role in (
        "registrar",
        "vice_chancellor",
        "deputy_registrar",
        "finance_team",
        "admin",
    ) or is_admin_email(user.email or "")

    # Determine who the two parties are
    faculty_user_id = str(approval.requester_id)
    department_user_id: str | None = None

    if is_requester or is_admin_or_reg:
        # Faculty or approval-stage actor initiating — find the other party.
        if department in ("registrar", "deputy_registrar", "finance_team"):
            # For pipeline-stage threads the other party is the current or
            # historical approver stored in requested_to, or the primary for
            # that role when requested_to has already been cleared.
            role_for_lookup = {
                "registrar": "registrar",
                "deputy_registrar": "deputy_registrar",
                "finance_team": "finance_team",
            }[department]
            assigned_email = (approval.requested_to or "").strip().lower()
            dept_u = await User.find_one({"email": assigned_email}) if assigned_email else None
            if not dept_u:
                from auth import get_primary_email_by_role as _get_pe
                fallback_email = await _get_pe(role_for_lookup)
                dept_u = await User.find_one({"email": fallback_email}) if fallback_email else None
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

    elif role == department or (role == "deputy_registrar" and department == "deputy_registrar") or (role == "finance_team" and department == "finance_team"):
        # Stage actor initiating their own thread side
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
    if role not in (
        "registrar",
        "vice_chancellor",
        "deputy_registrar",
        "finance_team",
        "admin",
    ) and not is_admin_email(user.email or ""):
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
        # When faculty replies to a clarification, revert approval status to pending
        # so the approver can act on it again.
        if is_reply_from_requester and (approval.status or "").lower() == "clarification_requested":
            approval.status = "pending"
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
    is_privileged = role in (
        "registrar",
        "vice_chancellor",
        "deputy_registrar",
        "finance_team",
        "admin",
    ) or is_admin_email(user.email or "")

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
    # When faculty replies to a clarification, revert approval status to pending
    if is_reply_from_requester and (approval.status or "").lower() == "clarification_requested":
        approval.status = "pending"
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

    role_normalized = (user.role or "").strip().lower()
    if not await user_may_act_on_approval_request(user, approval):
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

    audit_role = (
        role_normalized
        if role_normalized in ("registrar", "vice_chancellor", "deputy_registrar", "finance_team")
        else "registrar"
    )
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
            # Auto-create a stage-specific approval thread between the current
            # stage actor and the requester.  The department key is derived from
            # the pipeline_stage so deputy, finance and registrar each get their
            # own isolated thread and NEVER share history.
            active_stage = effective_pipeline_stage(approval)
            thread_dept_key = dept_key_for_stage(active_stage)
            dept_label_for_thread = DEPARTMENT_LABELS.get(thread_dept_key, "Registrar")
            try:
                await ensure_approval_thread_chat(
                    approval_request_id=str(approval.id),
                    department=thread_dept_key,
                    faculty_user_id=str(approval.requester_id),
                    department_user_id=str(user.id),
                    related_request_id=str(approval.id),
                    related_kind="approval_request",
                    title=f"{dept_label_for_thread} clarification – {approval.event_name}",
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
        ps_gate = effective_pipeline_stage(approval)

        if ps_gate == "deputy":
            approval.pipeline_stage = "after_deputy"
            approval.requested_to = None
            approval.discussion_status = None
            approval.deputy_decided_by = user.email
            approval.deputy_decided_at = datetime.utcnow()
            await approval.save()
            await record_workflow_action(
                event_id=approval.event_id,
                action_type=action_type_for_status(normalized_status),
                **ar_log_kwargs,
            )
            requester = await User.get(approval.requester_id)
            if requester and requester.email:
                try:
                    await notify_requester_text(
                        user,
                        requester.email,
                        f"Deputy Registrar approved: {approval.event_name}",
                        (
                            f"The Deputy Registrar approved your event \"{approval.event_name}\".\n\n"
                            "Sign in to the Event Booking portal, open My Events, and use "
                            "\"Send to finance department for approval\" to continue the workflow."
                        ),
                    )
                except Exception as exc:
                    logger.warning("Requester notification (deputy approved) failed: %s", exc)
            response_body = serialize_approval(approval)
            if idem_key:
                await store_response(idem_key, 200, response_body.model_dump(mode="json"))
            return response_body

        if ps_gate == "finance":
            approval.pipeline_stage = "after_finance"
            approval.requested_to = None
            approval.discussion_status = None
            approval.finance_decided_by = user.email
            approval.finance_decided_at = datetime.utcnow()
            await approval.save()
            await record_workflow_action(
                event_id=approval.event_id,
                action_type=action_type_for_status(normalized_status),
                **ar_log_kwargs,
            )
            requester = await User.get(approval.requester_id)
            if requester and requester.email:
                try:
                    await notify_requester_text(
                        user,
                        requester.email,
                        f"Finance approved: {approval.event_name}",
                        (
                            f"Finance has approved your event \"{approval.event_name}\".\n\n"
                            "Sign in to the Event Booking portal, open My Events, and use "
                            "\"Send to Registrar for approval\" to route the request to the Registrar "
                            "(or Vice Chancellor for high-budget events)."
                        ),
                    )
                except Exception as exc:
                    logger.warning("Requester notification (finance approved) failed: %s", exc)
            response_body = serialize_approval(approval)
            if idem_key:
                await store_response(idem_key, 200, response_body.model_dump(mode="json"))
            return response_body

        if ps_gate != "registrar":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="This approval is not at the final review stage.",
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

        approval.pipeline_stage = "complete"
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

    should_resolve_threads = normalized_status == "rejected" or (
        normalized_status == "approved"
        and approval.status == "approved"
        and getattr(approval, "event_id", None)
    )
    if should_resolve_threads:
        try:
            await resolve_approval_thread_status(str(approval.id), normalized_status)
        except Exception as exc:
            logger.warning("Resolve approval threads failed: %s", exc)

    if idem_key:
        await store_response(idem_key, 200, response_body.model_dump(mode="json"))
    return response_body
