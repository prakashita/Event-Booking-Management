import logging
import os
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile, status

from rate_limit import limiter

logger = logging.getLogger(__name__)

from auth import ensure_google_access_token, get_primary_email_by_role
from drive import upload_report_file
from event_status import event_has_ended, event_has_started
from models import ApprovalRequest, Event, MarketingDeliverable, MarketingRequest, User
from notifications import send_notification_email
from routers.deps import get_current_user
from decision_helpers import parse_requirement_decision_status, require_decision_comment
from requirement_decision_service import apply_requirement_decision
from schemas import MarketingDecision, MarketingRequestCreate, MarketingRequestResponse, MarketingDeliverableResponse

router = APIRouter(prefix="/marketing", tags=["Marketing"])


def _as_bool(value) -> bool:
    return bool(value) if value is not None else False


def _nested_flag(raw, section: str, key: str) -> bool:
    if raw is None:
        return False
    section_obj = raw.get(section) if isinstance(raw, dict) else getattr(raw, section, None)
    if section_obj is None:
        return False
    return _as_bool(section_obj.get(key) if isinstance(section_obj, dict) else getattr(section_obj, key, False))


def _normalize_marketing_requirements(
    marketing_requirements,
    *,
    poster_required: bool = False,
    video_required: bool = False,
    linkedin_post: bool = False,
    photography: bool = False,
    recording: bool = False,
):
    pre_event_poster = _nested_flag(marketing_requirements, "pre_event", "poster") or _as_bool(poster_required)
    pre_event_social = _nested_flag(marketing_requirements, "pre_event", "social_media") or _as_bool(linkedin_post)
    during_event_photo = _nested_flag(marketing_requirements, "during_event", "photo") or _as_bool(photography)
    during_event_video = _nested_flag(marketing_requirements, "during_event", "video") or _as_bool(video_required)
    post_event_social = _nested_flag(marketing_requirements, "post_event", "social_media")
    post_event_photo_upload = _nested_flag(marketing_requirements, "post_event", "photo_upload")
    post_event_video = _nested_flag(marketing_requirements, "post_event", "video") or _as_bool(recording)

    normalized = {
        "pre_event": {
            "poster": pre_event_poster,
            "social_media": pre_event_social,
        },
        "during_event": {
            "photo": during_event_photo,
            "video": during_event_video,
        },
        "post_event": {
            "social_media": post_event_social,
            "photo_upload": post_event_photo_upload,
            "video": post_event_video,
        },
    }

    flags = {
        "poster_required": normalized["pre_event"]["poster"],
        "video_required": normalized["during_event"]["video"],
        "linkedin_post": normalized["pre_event"]["social_media"] or normalized["post_event"]["social_media"],
        "photography": normalized["during_event"]["photo"] or normalized["post_event"]["photo_upload"],
        "recording": normalized["post_event"]["video"],
    }
    return normalized, flags


def _deliverable_field(d, key: str, default=None):
    if isinstance(d, dict):
        return d.get(key, default)
    return getattr(d, key, default)


def _serialize_deliverables(deliverables_list):
    result = []
    for d in deliverables_list or []:
        file_id = _deliverable_field(d, "file_id")
        is_na = _deliverable_field(d, "is_na", False)
        if not file_id and not is_na:
            continue
        if not file_id and is_na:
            file_id = "na"
        uploaded_at = _deliverable_field(d, "uploaded_at")
        if uploaded_at is None:
            uploaded_at = datetime.utcnow()
        result.append(
            MarketingDeliverableResponse(
                deliverable_type=_deliverable_field(d, "deliverable_type", "other"),
                file_id=file_id,
                file_name=_deliverable_field(d, "file_name", "N/A" if is_na else ""),
                web_view_link=_deliverable_field(d, "web_view_link"),
                uploaded_at=uploaded_at,
                is_na=is_na,
            )
        )
    return result


def _enforce_deliverable_upload_window(request_item: MarketingRequest, deliverable_type: str) -> None:
    """Pre-event uploads before start; post-event uploads after end (no during-event file uploads)."""
    start_d = request_item.start_date
    start_t = request_item.start_time
    end_d = request_item.end_date
    end_t = request_item.end_time

    normalized, _flags = _normalize_marketing_requirements(
        getattr(request_item, "marketing_requirements", None),
        poster_required=getattr(request_item, "poster_required", False),
        video_required=getattr(request_item, "video_required", False),
        linkedin_post=getattr(request_item, "linkedin_post", False),
        photography=getattr(request_item, "photography", False),
        recording=getattr(request_item, "recording", False),
    )
    pre_social = normalized["pre_event"]["social_media"]
    post_social = normalized["post_event"]["social_media"]
    started = event_has_started(start_d, start_t)
    ended = event_has_ended(end_d, end_t, start_date=start_d, start_time=start_t)

    if deliverable_type == "poster":
        if started:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Poster must be uploaded before the event starts.",
            )
        return

    if deliverable_type == "linkedin":
        if pre_social and not post_social:
            if started:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Pre-event social posts must be uploaded before the event starts.",
                )
        elif post_social and not pre_social:
            if not ended:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Post-event social posts must be uploaded after the event has ended.",
                )
        else:
            if started and not ended:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Social media deliverables must be uploaded before the event starts or after it ends.",
                )
        return

    if deliverable_type == "recording":
        if not ended:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Post-event video must be uploaded after the event has ended.",
            )
        return

    if deliverable_type == "photography":
        if not ended:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Post-event photo must be uploaded after the event has ended.",
            )
        return


def _marketing_upload_deliverable_types(request_item: MarketingRequest) -> list[str]:
    """Deliverable types marketing may submit. During-event (videoshoot, on-site photoshoot) has no file upload."""
    normalized, flags = _normalize_marketing_requirements(
        getattr(request_item, "marketing_requirements", None),
        poster_required=getattr(request_item, "poster_required", False),
        video_required=getattr(request_item, "video_required", False),
        linkedin_post=getattr(request_item, "linkedin_post", False),
        photography=getattr(request_item, "photography", False),
        recording=getattr(request_item, "recording", False),
    )
    types: list[str] = []
    if flags["poster_required"]:
        types.append("poster")
    if flags["linkedin_post"]:
        types.append("linkedin")
    if normalized["post_event"]["photo_upload"]:
        types.append("photography")
    if flags["recording"]:
        types.append("recording")
    return types


def _serialize_marketing_response(item: MarketingRequest) -> MarketingRequestResponse:
    normalized_requirements, flags = _normalize_marketing_requirements(
        getattr(item, "marketing_requirements", None),
        poster_required=getattr(item, "poster_required", False),
        video_required=getattr(item, "video_required", False),
        linkedin_post=getattr(item, "linkedin_post", False),
        photography=getattr(item, "photography", False),
        recording=getattr(item, "recording", False),
    )
    return MarketingRequestResponse(
        id=str(item.id),
        requester_id=item.requester_id,
        requester_email=item.requester_email,
        requested_to=item.requested_to,
        event_id=item.event_id,
        event_name=item.event_name,
        start_date=item.start_date,
        start_time=item.start_time,
        end_date=item.end_date,
        end_time=item.end_time,
        marketing_requirements=normalized_requirements,
        poster_required=flags["poster_required"],
        poster_dimension=item.poster_dimension,
        video_required=flags["video_required"],
        video_dimension=item.video_dimension,
        linkedin_post=flags["linkedin_post"],
        photography=flags["photography"],
        recording=flags["recording"],
        other_notes=item.other_notes,
        status=item.status,
        decided_at=item.decided_at,
        decided_by=item.decided_by,
        deliverables=_serialize_deliverables(getattr(item, "deliverables", None) or []),
        created_at=item.created_at,
    )


@router.post("/requests", response_model=MarketingRequestResponse, status_code=status.HTTP_201_CREATED)
async def create_marketing_request(
    payload: MarketingRequestCreate,
    user: User = Depends(get_current_user),
):
    if not payload.event_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Marketing request requires an approved event",
        )

    event = await Event.get(payload.event_id)
    if not event or event.created_by != str(user.id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Event not found",
        )

    if event_has_started(event.start_date, event.start_time):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Event has already started; cannot send marketing request.",
        )

    approval = await ApprovalRequest.find_one(ApprovalRequest.event_id == str(event.id))
    if not approval or approval.status != "approved":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Registrar must approve the event before sending marketing request",
        )

    requested_to = (payload.requested_to or "").strip().lower() or await get_primary_email_by_role("marketing")
    if not requested_to:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Marketing email is required",
        )

    normalized_requirements, flags = _normalize_marketing_requirements(
        payload.marketing_requirements,
        poster_required=payload.poster_required,
        video_required=payload.video_required,
        linkedin_post=payload.linkedin_post,
        photography=payload.photography,
        recording=payload.recording,
    )

    request_item = MarketingRequest(
        requester_id=str(user.id),
        requester_email=user.email,
        requested_to=requested_to,
        event_id=payload.event_id,
        event_name=payload.event_name,
        start_date=payload.start_date,
        start_time=payload.start_time,
        end_date=payload.end_date,
        end_time=payload.end_time,
        marketing_requirements=normalized_requirements,
        poster_required=flags["poster_required"],
        poster_dimension=payload.poster_dimension,
        video_required=flags["video_required"],
        video_dimension=payload.video_dimension,
        linkedin_post=flags["linkedin_post"],
        photography=flags["photography"],
        recording=flags["recording"],
        other_notes=payload.other_notes,
    )
    await request_item.insert()

    # Ensure a discussion thread exists between faculty and Marketing
    try:
        ar_for_event = await ApprovalRequest.find_one(ApprovalRequest.event_id == payload.event_id)
        if ar_for_event:
            from event_chat_service import ensure_dept_request_thread
            marketing_email = (payload.requested_to or "").strip().lower() or await get_primary_email_by_role("marketing")
            await ensure_dept_request_thread(
                approval_request_id=str(ar_for_event.id),
                department="marketing",
                faculty_user_id=str(user.id),
                dept_email=marketing_email,
                related_request_id=str(request_item.id),
                related_kind="marketing_request",
                event_name=request_item.event_name,
            )
    except Exception:
        pass

    subject = f"Marketing Request: {request_item.event_name}"
    body = (
        f"A new marketing request has been submitted for your approval.\n\n"
        f"Requester: {user.email}\n"
        f"Event: {request_item.event_name}\n"
        f"Date: {request_item.start_date} {request_item.start_time} - {request_item.end_date} {request_item.end_time}\n"
        f"Poster required: {'Yes' if request_item.poster_required else 'No'}\n"
        f"Videoshoot: {'Yes' if request_item.video_required else 'No'}\n"
        f"Social media post: {'Yes' if request_item.linkedin_post else 'No'}\n"
        f"Photoshoot / photo upload: {'Yes' if request_item.photography else 'No'}\n"
        f"Video upload (post-event): {'Yes' if request_item.recording else 'No'}\n"
    )
    if request_item.other_notes:
        body += f"\nAdditional notes: {request_item.other_notes}\n"
    body += "\nPlease approve or reject this request from your dashboard."
    await send_notification_email(
        recipient_email=requested_to,
        subject=subject,
        body=body,
        requester=user,
        fallback_role="marketing",
    )

    return _serialize_marketing_response(request_item)


@router.get("/inbox", response_model=list[MarketingRequestResponse])
async def list_marketing_inbox(user: User = Depends(get_current_user)):
    requested_to = (user.email or "").strip().lower()
    requests = await MarketingRequest.find(
        MarketingRequest.requested_to == requested_to
    ).sort("-created_at").to_list()
    return [_serialize_marketing_response(item) for item in requests]


@router.patch("/requests/{request_id}", response_model=MarketingRequestResponse)
async def decide_marketing_request(
    request_id: str,
    payload: MarketingDecision,
    user: User = Depends(get_current_user),
):
    comment = require_decision_comment(payload.comment)
    normalized_status = parse_requirement_decision_status(payload.status)

    request_item = await MarketingRequest.get(request_id)
    if not request_item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")

    if event_has_started(request_item.start_date, request_item.start_time):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Event has already started; approval or rejection is no longer allowed.",
        )

    if request_item.requested_to and request_item.requested_to != (user.email or "").strip().lower():
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed")

    await apply_requirement_decision(
        request_item,
        user=user,
        normalized_status=normalized_status,
        comment=comment,
        related_kind="marketing_request",
        role="marketing",
    )

    return _serialize_marketing_response(request_item)


@router.post("/requests/{request_id}/deliverable", response_model=MarketingRequestResponse)
@limiter.limit("30/minute")
async def upload_marketing_deliverable(
    request: Request,
    request_id: str,
    file: UploadFile = File(...),
    deliverable_type: str = Form(..., pattern="^(poster|photography|recording|linkedin|other)$"),
    user: User = Depends(get_current_user),
):
    """Upload a deliverable (poster, photo, video, etc.) for a marketing request. Only the marketing contact can upload."""
    try:
        request_item = await MarketingRequest.get(request_id)
        if not request_item:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")

        # Allow if user has marketing role OR is the recipient (request was sent to their email)
        user_role = (user.role or "").strip().lower()
        user_email = (user.email or "").strip().lower()
        requested_to = (request_item.requested_to or "").strip().lower()
        is_marketing_role = user_role == "marketing"
        is_recipient = requested_to and requested_to == user_email
        if not is_marketing_role and not is_recipient:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only the marketing contact or users with the marketing role can upload deliverables",
            )

        if deliverable_type != "other":
            allowed = set(_marketing_upload_deliverable_types(request_item))
            if deliverable_type not in allowed:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="This deliverable type does not require a file upload for this request.",
                )
            _enforce_deliverable_upload_window(request_item, deliverable_type)

        if not file.filename:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="File is required")
        contents = await file.read()
        max_size = 25 * 1024 * 1024  # 25MB
        if len(contents) > max_size:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="File too large (max 25MB)")

        folder_id = os.getenv("GOOGLE_DRIVE_FOLDER_ID", "")
        if not folder_id:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Google Drive folder not configured. Set GOOGLE_DRIVE_FOLDER_ID in .env.",
            )

        try:
            access_token = await ensure_google_access_token(user)
            drive_file = upload_report_file(
                access_token=access_token,
                file_name=file.filename,
                file_bytes=contents,
                mime_type=file.content_type or "application/octet-stream",
                folder_id=folder_id,
            )
        except HTTPException:
            raise
        except Exception as exc:
            logger.exception("Marketing deliverable Drive upload failed")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Unable to upload file to Drive: {exc!s}",
            ) from exc

        deliverable = MarketingDeliverable(
            deliverable_type=deliverable_type,
            file_id=drive_file.get("id", ""),
            file_name=drive_file.get("name", file.filename),
            web_view_link=drive_file.get("webViewLink"),
            uploaded_at=datetime.utcnow(),
        )
        existing = getattr(request_item, "deliverables", None) or []
        request_item.deliverables = list(existing) + [deliverable]
        await request_item.save()

        return _serialize_marketing_response(request_item)
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Marketing deliverable upload failed")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc) or "Upload failed",
        ) from exc


@router.post("/requests/{request_id}/deliverables/batch", response_model=MarketingRequestResponse)
@limiter.limit("30/minute")
async def upload_marketing_deliverables_batch(
    request: Request,
    request_id: str,
    user: User = Depends(get_current_user),
    na_poster: Optional[str] = Form(None),
    na_linkedin: Optional[str] = Form(None),
    na_photography: Optional[str] = Form(None),
    na_recording: Optional[str] = Form(None),
    file_poster: Optional[UploadFile] = File(None),
    file_linkedin: Optional[UploadFile] = File(None),
    file_photography: Optional[UploadFile] = File(None),
    file_recording: Optional[UploadFile] = File(None),
):
    """Submit deliverables for uploadable requirements (pre/post only; during-event needs have no files)."""
    try:
        request_item = await MarketingRequest.get(request_id)
        if not request_item:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")

        user_role = (user.role or "").strip().lower()
        user_email = (user.email or "").strip().lower()
        requested_to = (request_item.requested_to or "").strip().lower()
        is_marketing_role = user_role == "marketing"
        is_recipient = requested_to and requested_to == user_email
        if not is_marketing_role and not is_recipient:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only the marketing contact or users with the marketing role can upload deliverables",
            )

        folder_id = os.getenv("GOOGLE_DRIVE_FOLDER_ID", "")
        if not folder_id:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Google Drive folder not configured. Set GOOGLE_DRIVE_FOLDER_ID in .env.",
            )

        na_map = {"poster": na_poster, "linkedin": na_linkedin, "photography": na_photography, "recording": na_recording}
        file_map = {"poster": file_poster, "linkedin": file_linkedin, "photography": file_photography, "recording": file_recording}

        existing = list(getattr(request_item, "deliverables", None) or [])
        existing_by_type = {_deliverable_field(d, "deliverable_type"): d for d in existing}

        access_token = None

        for dtype in _marketing_upload_deliverable_types(request_item):
            is_na = bool(na_map.get(dtype))
            uf = file_map.get(dtype)

            if is_na or (uf and uf.filename):
                _enforce_deliverable_upload_window(request_item, dtype)

            if is_na:
                existing_by_type[dtype] = MarketingDeliverable(
                    deliverable_type=dtype,
                    file_id="na",
                    file_name="N/A",
                    is_na=True,
                    uploaded_at=datetime.utcnow(),
                )
            elif uf and uf.filename:
                contents = await uf.read()
                max_size = 25 * 1024 * 1024
                if len(contents) > max_size:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"{dtype}: File too large (max 25MB)",
                    )
                if access_token is None:
                    access_token = await ensure_google_access_token(user)
                drive_file = upload_report_file(
                    access_token=access_token,
                    file_name=uf.filename,
                    file_bytes=contents,
                    mime_type=uf.content_type or "application/octet-stream",
                    folder_id=folder_id,
                )
                existing_by_type[dtype] = MarketingDeliverable(
                    deliverable_type=dtype,
                    file_id=drive_file.get("id", ""),
                    file_name=drive_file.get("name", uf.filename),
                    web_view_link=drive_file.get("webViewLink"),
                    uploaded_at=datetime.utcnow(),
                )

        request_item.deliverables = [existing_by_type[k] for k in sorted(existing_by_type.keys())]
        await request_item.save()

        return _serialize_marketing_response(request_item)
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Marketing deliverables batch upload failed")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc) or "Upload failed",
        ) from exc


@router.get("/requests/me", response_model=list[MarketingRequestResponse])
async def list_my_marketing_requests(user: User = Depends(get_current_user)):
    requests = await MarketingRequest.find(
        MarketingRequest.requester_id == str(user.id)
    ).sort("-created_at").to_list()
    return [_serialize_marketing_response(item) for item in requests]
