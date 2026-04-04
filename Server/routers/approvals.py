import base64
import logging
import os
import re
from datetime import datetime

from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, UploadFile, status
import requests

from auth import ensure_google_access_token
from drive import upload_report_file
from idempotency import get_cached_response, get_idempotency_key, store_response
from models import ApprovalRequest, Event, FacilityManagerRequest, ItRequest, MarketingRequest, TransportRequest, User
from event_status import combine_datetime, compute_event_status, event_has_started
from rate_limit import limiter
from routers.admin import serialize_approval
from routers.deps import get_current_user
from routers.events import get_expected_budget_breakdown_filename, sync_event_to_google_calendar
from decision_helpers import action_type_for_status, parse_registrar_decision_status, require_decision_comment
from schemas import ApprovalDecision, ApprovalRequestResponse, PaginatedResponse
from workflow_action_service import record_workflow_action

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
    email = (user.email or "").strip()
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

    comment = require_decision_comment(payload.comment)
    normalized_status = parse_registrar_decision_status(payload.status)

    approval = await ApprovalRequest.get(request_id)
    if not approval:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")

    if event_has_started(approval.start_date, approval.start_time):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Event has already started; approval or rejection is no longer allowed.",
        )

    approver_email = (user.email or "").strip().lower()
    if approval.requested_to and approval.requested_to.strip().lower() != approver_email:
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

    ar_log_kwargs = dict(
        approval_request_id=str(approval.id),
        related_kind="approval_request",
        related_id=str(approval.id),
        role="registrar",
        comment=comment,
        action_by_email=user.email or "",
        action_by_user_id=str(user.id),
    )

    if normalized_status == "clarification_requested":
        approval.status = "clarification_requested"
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
    elif normalized_status == "rejected":
        approval.status = "rejected"
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
        approval.decided_by = user.email
        approval.decided_at = datetime.utcnow()
        await approval.save()
        await record_workflow_action(
            event_id=approval.event_id,
            action_type=action_type_for_status(normalized_status),
            **ar_log_kwargs,
        )

    response_body = serialize_approval(approval)
    if idem_key:
        await store_response(idem_key, 200, response_body.model_dump(mode="json"))
    return response_body
