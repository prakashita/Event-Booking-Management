import json
import os
from datetime import datetime
from typing import Optional

from beanie import PydanticObjectId
from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Request, UploadFile, status

from auth import ensure_google_access_token
from drive import upload_file_to_nested_folder, upload_report_file
from models import StudentAchievement, StudentAchievementFile, StudentAchievementStudent, User
from rate_limit import limiter
from routers.deps import get_current_user, require_admin_only
from upload_validation import MAX_PDF_UPLOAD_BYTES, PDF_SIZE_ERROR_DETAIL
from schemas import (
    PaginatedResponse,
    StudentAchievementFileResponse,
    StudentAchievementPatch,
    StudentAchievementResponse,
    StudentAchievementStudentPayload,
)

try:
    from routers.iqac import _criteria_structure
except Exception:  # pragma: no cover - defensive import guard for optional router wiring
    _criteria_structure = None


router = APIRouter(prefix="/student-achievements", tags=["Student Achievements"])

MAX_ATTACHMENT_FILES = 15
MAX_FILE_BYTES = 25 * 1024 * 1024
ADMIN_VIEW_ROLES = {"admin"}
EDITABLE_TEXT_FIELDS = {
    "activity_description",
    "additional_context_objective",
    "social_media_writeup",
    "iqac_criterion_id",
    "iqac_subfolder_id",
    "iqac_item_id",
    "iqac_description",
}


def _clean(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    value = str(value).strip()
    return value or None


def _parse_json_list(raw: Optional[str], field_name: str) -> list:
    if not raw:
        return []
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail=f"{field_name} must be valid JSON") from exc
    if not isinstance(parsed, list):
        raise HTTPException(status_code=400, detail=f"{field_name} must be a list")
    return parsed


def _student_name(student: StudentAchievementStudent) -> str:
    return (getattr(student, "student_name", None) or getattr(student, "name", None) or "").strip()


def _parse_students(raw: Optional[str]) -> list[StudentAchievementStudent]:
    rows = _parse_json_list(raw, "students")
    students: list[StudentAchievementStudent] = []
    for row in rows:
        if isinstance(row, str):
            student_name = row.strip()
            batch = None
            course = None
        elif isinstance(row, dict):
            student_name = str(row.get("student_name") or row.get("name") or "").strip()
            batch = _clean(row.get("batch"))
            course = _clean(row.get("course"))
        else:
            continue
        if student_name:
            students.append(StudentAchievementStudent(student_name=student_name, batch=batch, course=course))
    return students


def _payload_students(rows: Optional[list[StudentAchievementStudentPayload]]) -> list[StudentAchievementStudent]:
    students: list[StudentAchievementStudent] = []
    for row in rows or []:
        student_name = (row.student_name or row.name or "").strip()
        if student_name:
            students.append(
                StudentAchievementStudent(
                    student_name=student_name,
                    batch=_clean(row.batch),
                    course=_clean(row.course),
                )
            )
    return students


def _parse_platforms(raw: Optional[str]) -> list[str]:
    rows = _parse_json_list(raw, "suggested_platforms")
    return [str(item).strip() for item in rows if str(item or "").strip()]


def _can_view_all(user: User) -> bool:
    role = (user.role or "").strip().lower()
    return role in ADMIN_VIEW_ROLES


def _is_admin_actor(user: User) -> bool:
    return (user.role or "").strip().lower() == "admin"


def _is_owner(item: StudentAchievement, user: User) -> bool:
    return item.created_by == str(user.id)


def _serialize_file(file: StudentAchievementFile) -> StudentAchievementFileResponse:
    return StudentAchievementFileResponse(
        file_id=file.file_id,
        file_name=file.file_name,
        web_view_link=file.web_view_link,
        content_type=file.content_type,
        size=file.size,
        uploaded_at=file.uploaded_at,
    )


def _all_attachments(item: StudentAchievement) -> list[StudentAchievementFile]:
    attachments = list(getattr(item, "attachments", None) or [])
    if not attachments:
        attachments.extend(getattr(item, "assets", None) or [])
        attachments.extend(getattr(item, "proofs", None) or [])
    return attachments


def _derived_title(students: list[StudentAchievementStudent], description: Optional[str], legacy_title: Optional[str] = None) -> str:
    title = _clean(legacy_title)
    if title:
        return title
    names = [_student_name(student) for student in students if _student_name(student)]
    if names:
        return f"Student Achievement - {', '.join(names[:2])}{' +' if len(names) > 2 else ''}"
    description = _clean(description)
    if description:
        return description[:120]
    return "Student Achievement"


def _audit_entry(action: str, user: User, changed_fields: Optional[list[str]] = None) -> dict:
    return {
        "action": action,
        "actor": str(user.id),
        "actor_name": user.name,
        "actor_email": user.email,
        "timestamp": datetime.utcnow().isoformat(),
        "changed_fields": changed_fields or [],
    }


def _to_response(item: StudentAchievement) -> StudentAchievementResponse:
    attachments = _all_attachments(item)
    activity_description = item.activity_description or item.detailed_writeup or item.brief_context
    additional_context = item.additional_context_objective or item.additional_notes
    social_writeup = item.social_media_writeup or item.detailed_writeup
    return StudentAchievementResponse(
        id=str(item.id),
        achievement_title=_derived_title(item.students or [], activity_description, item.achievement_title),
        students=[
            StudentAchievementStudentPayload(
                student_name=_student_name(s),
                batch=getattr(s, "batch", None),
                course=getattr(s, "course", None),
                name=getattr(s, "name", None),
                registration_number=getattr(s, "registration_number", None),
            )
            for s in (item.students or [])
        ],
        activity_description=activity_description,
        additional_context_objective=additional_context,
        social_media_writeup=social_writeup,
        attachments=[_serialize_file(f) for f in attachments],
        iqac_criterion_id=item.iqac_criterion_id,
        iqac_subfolder_id=item.iqac_subfolder_id,
        iqac_item_id=item.iqac_item_id,
        iqac_description=item.iqac_description,
        department_programme=item.department_programme,
        year_semester=item.year_semester,
        faculty_mentor=item.faculty_mentor,
        achievement_category=item.achievement_category,
        achievement_date=item.achievement_date,
        activity_name=item.activity_name,
        organising_institution=item.organising_institution,
        level=item.level,
        award_recognition=item.award_recognition,
        brief_context=item.brief_context,
        detailed_writeup=item.detailed_writeup,
        suggested_platforms=item.suggested_platforms or [],
        preferred_posting_date=item.preferred_posting_date,
        assets=[_serialize_file(f) for f in (item.assets or [])],
        proofs=[_serialize_file(f) for f in (item.proofs or [])],
        consent_confirmed=item.consent_confirmed,
        additional_notes=item.additional_notes,
        status=item.status,
        created_by=item.created_by,
        created_by_name=item.created_by_name,
        created_by_email=item.created_by_email,
        created_at=item.created_at,
        updated_by=item.updated_by,
        updated_by_name=item.updated_by_name,
        updated_by_email=item.updated_by_email,
        updated_at=item.updated_at,
        audit_log=item.audit_log or [],
    )


async def _upload_files(files: Optional[list[UploadFile]], user: User, folder_id: Optional[str]) -> list[StudentAchievementFile]:
    selected = [file for file in (files or []) if file and file.filename]
    if len(selected) > MAX_ATTACHMENT_FILES:
        raise HTTPException(status_code=400, detail=f"At most {MAX_ATTACHMENT_FILES} files are allowed")
    if not selected:
        return []

    access_token = await ensure_google_access_token(user)
    uploaded: list[StudentAchievementFile] = []
    for file in selected:
        contents = await file.read()
        # PDFs must not exceed 15 MB.
        if (
            (file.content_type or "").lower() == "application/pdf"
            or (file.filename or "").lower().endswith(".pdf")
        ) and len(contents) > MAX_PDF_UPLOAD_BYTES:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail=PDF_SIZE_ERROR_DETAIL,
            )
        if len(contents) > MAX_FILE_BYTES:
            raise HTTPException(status_code=400, detail=f"{file.filename} is too large (max 25MB)")
        if folder_id:
            _now = datetime.utcnow()
            drive_file = upload_file_to_nested_folder(
                access_token=access_token,
                file_name=file.filename,
                file_bytes=contents,
                mime_type=file.content_type or "application/octet-stream",
                root_folder_id=folder_id,
                folder_path_parts=[_now.strftime("%Y"), _now.strftime("%Y-%m")],
                allow_root_fallback=True,
            )
        else:
            drive_file = upload_report_file(
                access_token=access_token,
                file_name=file.filename,
                file_bytes=contents,
                mime_type=file.content_type or "application/octet-stream",
                folder_id=None,
                allow_root_fallback=True,
            )
        uploaded.append(
            StudentAchievementFile(
                file_id=drive_file.get("id", ""),
                file_name=drive_file.get("name", file.filename),
                web_view_link=drive_file.get("webViewLink"),
                content_type=file.content_type,
                size=len(contents),
                uploaded_at=datetime.utcnow(),
            )
        )
    return uploaded


async def _get_visible_achievement(achievement_id: str, user: User) -> StudentAchievement:
    try:
        oid = PydanticObjectId(achievement_id)
    except Exception as exc:
        raise HTTPException(status_code=404, detail="Student achievement not found") from exc
    item = await StudentAchievement.get(oid)
    if not item:
        raise HTTPException(status_code=404, detail="Student achievement not found")
    if not (_can_view_all(user) or _is_owner(item, user)):
        raise HTTPException(status_code=403, detail="Access denied")
    return item


@router.get("/iqac-criteria")
async def get_student_achievement_iqac_criteria(user: User = Depends(get_current_user)):
    if not _criteria_structure:
        return []
    return _criteria_structure()


@router.post("", response_model=StudentAchievementResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit("30/minute")
async def create_student_achievement(
    request: Request,
    students: str = Form(default="[]"),
    activity_description: Optional[str] = Form(default=None),
    additional_context_objective: Optional[str] = Form(default=None),
    suggested_platforms: str = Form(default="[]"),
    social_media_writeup: Optional[str] = Form(default=None),
    iqac_criterion_id: Optional[str] = Form(default=None),
    iqac_subfolder_id: Optional[str] = Form(default=None),
    iqac_item_id: Optional[str] = Form(default=None),
    iqac_description: Optional[str] = Form(default=None),
    achievement_title: Optional[str] = Form(default=None),
    attachments: Optional[list[UploadFile]] = File(default=None),
    assets: Optional[list[UploadFile]] = File(default=None),
    proofs: Optional[list[UploadFile]] = File(default=None),
    user: User = Depends(get_current_user),
):
    student_rows = _parse_students(students)
    if not student_rows:
        raise HTTPException(status_code=400, detail="At least one student is required")
    if not _clean(activity_description):
        raise HTTPException(status_code=400, detail="Description of activity and achievement is required")

    upload_candidates = list(attachments or []) + list(assets or []) + list(proofs or [])
    folder_id = os.getenv("STUDENT_ACHIEVEMENTS_DRIVE_FOLDER_ID") or os.getenv("GOOGLE_DRIVE_FOLDER_ID") or None
    try:
        attachment_files = await _upload_files(upload_candidates, user, folder_id)
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Unable to upload files: {exc}") from exc

    now = datetime.utcnow()
    achievement = StudentAchievement(
        achievement_title=_derived_title(student_rows, activity_description, achievement_title),
        students=student_rows,
        activity_description=_clean(activity_description),
        additional_context_objective=_clean(additional_context_objective),
        suggested_platforms=_parse_platforms(suggested_platforms),
        social_media_writeup=_clean(social_media_writeup),
        attachments=attachment_files,
        iqac_criterion_id=_clean(iqac_criterion_id),
        iqac_subfolder_id=_clean(iqac_subfolder_id),
        iqac_item_id=_clean(iqac_item_id),
        iqac_description=_clean(iqac_description),
        created_by=str(user.id),
        created_by_name=user.name,
        created_by_email=user.email,
        updated_by=str(user.id),
        updated_by_name=user.name,
        updated_by_email=user.email,
        created_at=now,
        updated_at=now,
        audit_log=[_audit_entry("created", user)],
    )
    await achievement.insert()
    return _to_response(achievement)


@router.get("", response_model=PaginatedResponse[StudentAchievementResponse])
async def list_student_achievements(
    user: User = Depends(get_current_user),
    search: Optional[str] = Query(default=None),
    platform: Optional[str] = Query(default=None),
    iqac_criterion_id: Optional[str] = Query(default=None),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
):
    base_query = {} if _can_view_all(user) else {"created_by": str(user.id)}
    query = StudentAchievement.find(base_query) if base_query else StudentAchievement.find_all()
    items = await query.sort("-created_at").to_list()

    def matches(item: StudentAchievement) -> bool:
        if platform and platform not in (item.suggested_platforms or []):
            return False
        if iqac_criterion_id and (item.iqac_criterion_id or "") != iqac_criterion_id:
            return False
        if search:
            haystack = " ".join(
                [
                    item.achievement_title or "",
                    item.activity_description or "",
                    item.additional_context_objective or "",
                    item.social_media_writeup or "",
                    item.created_by_name or "",
                    item.created_by_email or "",
                    " ".join(_student_name(s) for s in (item.students or [])),
                    " ".join((getattr(s, "batch", None) or "") for s in (item.students or [])),
                    " ".join((getattr(s, "course", None) or "") for s in (item.students or [])),
                ]
            ).lower()
            return search.strip().lower() in haystack
        return True

    filtered = [item for item in items if matches(item)]
    total = len(filtered)
    page = filtered[offset : offset + limit]
    next_offset = offset + limit if offset + limit < total else None
    return PaginatedResponse[StudentAchievementResponse](
        items=[_to_response(item) for item in page],
        total=total,
        limit=limit,
        offset=offset,
        next_offset=next_offset,
    )


@router.get("/{achievement_id}", response_model=StudentAchievementResponse)
async def get_student_achievement(
    achievement_id: str,
    user: User = Depends(get_current_user),
):
    return _to_response(await _get_visible_achievement(achievement_id, user))


@router.patch("/{achievement_id}", response_model=StudentAchievementResponse)
async def update_student_achievement(
    achievement_id: str,
    request: Request,
    user: User = Depends(get_current_user),
):
    item = await _get_visible_achievement(achievement_id, user)
    if _is_admin_actor(user):
        raise HTTPException(status_code=403, detail="Admin users can view and delete student achievements, not edit them")
    if not _is_owner(item, user):
        raise HTTPException(status_code=403, detail="Only the owner can edit this submission")

    content_type = (request.headers.get("content-type") or "").lower()
    changed_fields: list[str] = []

    if "multipart/form-data" in content_type:
        form = await request.form()
        if "students" in form:
            item.students = _parse_students(str(form.get("students") or "[]"))
            changed_fields.append("students")
        if "suggested_platforms" in form:
            item.suggested_platforms = _parse_platforms(str(form.get("suggested_platforms") or "[]"))
            changed_fields.append("suggested_platforms")
        for field in EDITABLE_TEXT_FIELDS:
            if field in form:
                setattr(item, field, _clean(form.get(field)))
                changed_fields.append(field)
        uploads = [file for file in form.getlist("attachments") if getattr(file, "filename", None)]
        if uploads:
            folder_id = os.getenv("STUDENT_ACHIEVEMENTS_DRIVE_FOLDER_ID") or os.getenv("GOOGLE_DRIVE_FOLDER_ID") or None
            try:
                attachment_files = await _upload_files(uploads, user, folder_id)
            except RuntimeError as exc:
                raise HTTPException(status_code=500, detail=str(exc)) from exc
            item.attachments = list(item.attachments or []) + attachment_files
            changed_fields.append("attachments")
    else:
        try:
            raw_updates = await request.json()
        except Exception as exc:
            raise HTTPException(status_code=400, detail="Invalid JSON payload") from exc
        payload = StudentAchievementPatch.model_validate(raw_updates or {})
        updates = payload.model_dump(exclude_unset=True)
        for field, value in updates.items():
            if field == "students":
                item.students = _payload_students(payload.students)
                changed_fields.append(field)
            elif field == "suggested_platforms":
                item.suggested_platforms = [str(v).strip() for v in (value or []) if str(v or "").strip()]
                changed_fields.append(field)
            elif field in EDITABLE_TEXT_FIELDS:
                setattr(item, field, _clean(value))
                changed_fields.append(field)

    if not item.students:
        raise HTTPException(status_code=400, detail="At least one student is required")
    if not _clean(item.activity_description):
        raise HTTPException(status_code=400, detail="Description of activity and achievement is required")

    item.achievement_title = _derived_title(item.students, item.activity_description, item.achievement_title)
    item.updated_by = str(user.id)
    item.updated_by_name = user.name
    item.updated_by_email = user.email
    item.updated_at = datetime.utcnow()
    item.audit_log = list(item.audit_log or []) + [_audit_entry("updated", user, changed_fields)]
    await item.save()
    return _to_response(item)


@router.delete("/{achievement_id}")
async def delete_student_achievement(
    achievement_id: str,
    admin: User = Depends(require_admin_only),
):
    try:
        oid = PydanticObjectId(achievement_id)
    except Exception as exc:
        raise HTTPException(status_code=404, detail="Student achievement not found") from exc
    item = await StudentAchievement.get(oid)
    if not item:
        raise HTTPException(status_code=404, detail="Student achievement not found")
    item.audit_log = list(item.audit_log or []) + [_audit_entry("deleted", admin)]
    await item.delete()
    return {"status": "deleted", "id": achievement_id}
