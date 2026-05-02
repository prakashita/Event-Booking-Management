"""
IQAC Data Collection API: criteria tree, file list/upload/delete/download.
Access restricted to users with IQAC role.
"""
import os
import re
import uuid
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List

from beanie import PydanticObjectId
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from fastapi.responses import FileResponse, Response

from models import IQACFile, IQACSSRHistory, IQACSSRSection, User
from routers.deps import IQAC_DELETE_ALLOWED_ROLES, require_iqac
from schemas import IQACSSRHistoryResponse, IQACSSRSectionResponse, IQACSSRSectionUpdate

router = APIRouter(prefix="/iqac", tags=["iqac"])

# Max file size 10MB
MAX_FILE_SIZE = 10 * 1024 * 1024
ALLOWED_EXTENSIONS = {".pdf", ".doc", ".docx"}
ALLOWED_CONTENT_TYPES = {
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
}


def resolve_iqac_uploads_dir() -> str:
    env_dir = os.getenv("UPLOADS_DIR")
    if env_dir:
        base = os.path.abspath(env_dir)
    elif os.getenv("VERCEL") == "1":
        base = "/tmp/uploads"
    else:
        base = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "uploads"))
    iqac_dir = os.path.join(base, "iqac")
    try:
        os.makedirs(iqac_dir, exist_ok=True)
    except OSError:
        pass
    return iqac_dir


IQAC_UPLOADS_DIR = resolve_iqac_uploads_dir()


def _repo_root() -> str:
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def _resolve_template_file_path(filename: str) -> str | None:
    """Find a bundled IQAC template file without exposing it as a public static asset."""
    env_dir = os.getenv("IQAC_TEMPLATES_DIR")
    candidates = []
    if env_dir:
        candidates.append(os.path.join(os.path.abspath(env_dir), filename))
    root = _repo_root()
    candidates.extend([
        os.path.join(root, "Server", "templates", "iqac", filename),
        os.path.join(root, "Client", "src", filename),
    ])
    for path in candidates:
        if os.path.isfile(path):
            return path
    return None


IQAC_TEMPLATE_DEFINITIONS = (
    {
        "id": "all-templates",
        "name": "IQAC Data Templates",
        "file_name": "IQAC Data Templates.docx",
        "type": "DOCX",
        "content_type": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    },
)

SSR_SECTION_KEYS = ("executive_summary", "university_profile", "extended_profile", "qif")


def _format_ssr_section(
    section_key: str,
    doc: IQACSSRSection | None = None,
    *,
    no_changes: bool = False,
    message: str | None = None,
) -> dict[str, Any]:
    if not doc:
        return {
            "id": None,
            "section_key": section_key,
            "data": {},
            "no_changes": no_changes,
            "message": message,
            "created_by": None,
            "created_by_name": None,
            "updated_by": None,
            "updated_by_name": None,
            "updated_by_email": None,
            "created_at": None,
            "updated_at": None,
        }
    created_at = doc.created_at
    updated_at = doc.updated_at
    if created_at and created_at.tzinfo is None:
        created_at = created_at.replace(tzinfo=timezone.utc)
    if updated_at and updated_at.tzinfo is None:
        updated_at = updated_at.replace(tzinfo=timezone.utc)
    return {
        "id": str(doc.id),
        "section_key": doc.section_key,
        "data": doc.data or {},
        "no_changes": no_changes,
        "message": message,
        "created_by": doc.created_by,
        "created_by_name": getattr(doc, "created_by_name", None),
        "updated_by": doc.updated_by,
        "updated_by_name": getattr(doc, "updated_by_name", None),
        "updated_by_email": getattr(doc, "updated_by_email", None),
        "created_at": created_at.isoformat() if created_at else None,
        "updated_at": updated_at.isoformat() if updated_at else None,
    }


def _normalize_for_compare(value: Any) -> Any:
    """Return plain JSON-like data with dictionaries sorted for stable deep comparison."""
    if isinstance(value, dict):
        return {key: _normalize_for_compare(value[key]) for key in sorted(value.keys())}
    if isinstance(value, list):
        return [_normalize_for_compare(item) for item in value]
    return value


def _has_meaningful_value(value: Any) -> bool:
    if value is None:
        return False
    if isinstance(value, str):
        return bool(value.strip())
    if isinstance(value, (int, float, bool)):
        return bool(value)
    if isinstance(value, list):
        return any(_has_meaningful_value(item) for item in value)
    if isinstance(value, dict):
        return any(_has_meaningful_value(item) for item in value.values())
    return True


def _diff_value_type(old_value: Any, new_value: Any) -> str:
    if old_value is None and new_value is not None:
        return "added"
    if old_value is not None and new_value is None:
        return "removed"
    return "changed"


def _compute_field_diffs(old_data: Any, new_data: Any, prefix: str = "") -> dict[str, dict[str, Any]]:
    """Return field path -> previous/new diff entries for nested dict/list values."""
    if isinstance(old_data, dict) and isinstance(new_data, dict):
        diffs: dict[str, dict[str, Any]] = {}
        all_keys = sorted(set(old_data.keys()) | set(new_data.keys()))
        for key in all_keys:
            path = f"{prefix}.{key}" if prefix else str(key)
            old_value = old_data.get(key)
            new_value = new_data.get(key)
            if _normalize_for_compare(old_value) == _normalize_for_compare(new_value):
                continue
            if isinstance(old_value, dict) and isinstance(new_value, dict):
                nested = _compute_field_diffs(old_value, new_value, path)
                diffs.update(nested or {
                    path: {
                        "previous": old_value,
                        "new": new_value,
                        "type": _diff_value_type(old_value, new_value),
                    }
                })
            else:
                diffs[path] = {
                    "previous": old_value,
                    "new": new_value,
                    "type": _diff_value_type(old_value, new_value),
                }
        return diffs

    if _normalize_for_compare(old_data) == _normalize_for_compare(new_data):
        return {}
    return {
        prefix or "data": {
            "previous": old_data,
            "new": new_data,
            "type": _diff_value_type(old_data, new_data),
        }
    }


def _compute_changed_fields(old_data: dict, new_data: dict) -> list[str]:
    return sorted(_compute_field_diffs(old_data, new_data).keys())


def _serialize_ssr_history(history: IQACSSRHistory) -> dict[str, Any]:
    edited_at = history.edited_at
    expires_at = history.expires_at
    if edited_at and edited_at.tzinfo is None:
        edited_at = edited_at.replace(tzinfo=timezone.utc)
    if expires_at and expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    edited_by_user_id = getattr(history, "edited_by_user_id", None) or getattr(history, "edited_by", None)
    return {
        "id": str(history.id),
        "section_key": history.section_key,
        "previous_data": history.previous_data or {},
        "new_data": history.new_data or {},
        "changed_fields": history.changed_fields or [],
        "field_diffs": getattr(history, "field_diffs", None) or {},
        "change_summary": history.change_summary,
        "edited_by": getattr(history, "edited_by", None) or edited_by_user_id,
        "edited_by_user_id": edited_by_user_id,
        "edited_by_name": history.edited_by_name,
        "edited_by_email": history.edited_by_email,
        "edited_at": edited_at.isoformat() if edited_at else None,
        "expires_at": expires_at.isoformat() if expires_at else None,
    }


def _validate_ssr_section_key(section_key: str) -> str:
    normalized = (section_key or "").strip().lower()
    if normalized not in SSR_SECTION_KEYS:
        raise HTTPException(status_code=404, detail="SSR section not found")
    return normalized


async def _purge_expired_ssr_history(now: datetime) -> None:
    cutoff = now - timedelta(days=5)
    await IQACSSRHistory.find(
        {"$or": [{"edited_at": {"$lt": cutoff}}, {"expires_at": {"$lt": now}}]}
    ).delete()


# NAAC IQAC 7-criteria structure: criterion title → sub-criteria (1.1, 1.2, …) → items (1.1.1, 1.1.2, …)
CRITERION_ORDER = (
    "Curricular Aspects",
    "Teaching-Learning & Evaluation",
    "Research, Innovations & Extension",
    "Infrastructure & Learning Resources",
    "Student Support & Progression",
    "Governance, Leadership & Management",
    "Institutional Values & Best Practices",
)

NAAC_CRITERIA = {
    "Curricular Aspects": {
        "1.1": {
            "name": "Curriculum Design and Development",
            "items": {
                "1.1.1": "Curricular Planning",
                "1.1.2": "Academic Flexibility",
                "1.1.3": "Curriculum Enrichment",
                "1.1.4": "Feedback System",
            },
        },
        "1.2": {
            "name": "Academic Flexibility",
            "items": {
                "1.2.1": "Choice Based Credit System",
                "1.2.2": "Range of Courses",
                "1.2.3": "Value Added Courses",
            },
        },
        "1.3": {
            "name": "Curriculum Enrichment",
            "items": {
                "1.3.1": "Industry Integration",
                "1.3.2": "Skill Development",
                "1.3.3": "Interdisciplinary Programs",
            },
        },
        "1.4": {
            "name": "Feedback System",
            "items": {
                "1.4.1": "Stakeholder Feedback",
                "1.4.2": "Alumni Feedback",
                "1.4.3": "Employer Feedback",
            },
        },
    },
    "Teaching-Learning & Evaluation": {
        "2.1": {
            "name": "Student Enrolment and Profile",
            "items": {
                "2.1.1": "Enrolment Process",
                "2.1.2": "Student Diversity",
                "2.1.3": "Admission Process",
            },
        },
        "2.2": {
            "name": "Catering to Student Diversity",
            "items": {
                "2.2.1": "Student Support Services",
                "2.2.2": "Learning Support",
                "2.2.3": "Special Needs Support",
            },
        },
        "2.3": {
            "name": "Teaching-Learning Process",
            "items": {
                "2.3.1": "Teaching Methods",
                "2.3.2": "Learning Resources",
                "2.3.3": "ICT Integration",
            },
        },
        "2.4": {
            "name": "Teacher Quality",
            "items": {
                "2.4.1": "Faculty Recruitment",
                "2.4.2": "Faculty Development",
                "2.4.3": "Faculty Performance",
            },
        },
        "2.5": {
            "name": "Evaluation Process and Reforms",
            "items": {
                "2.5.1": "Assessment Methods",
                "2.5.2": "Examination Reforms",
                "2.5.3": "Result Analysis",
            },
        },
        "2.6": {
            "name": "Student Performance and Learning Outcomes",
            "items": {
                "2.6.1": "Academic Performance",
                "2.6.2": "Placement Records",
                "2.6.3": "Alumni Achievements",
            },
        },
    },
    "Research, Innovations & Extension": {
        "3.1": {"name": "Promotion of Research", "items": {"3.1.1": "Research Policy", "3.1.2": "Research Facilities", "3.1.3": "Research Grants"}},
        "3.2": {"name": "Resource Mobilization for Research", "items": {"3.2.1": "External Funding", "3.2.2": "Internal Funding", "3.2.3": "Industry Collaboration"}},
        "3.3": {"name": "Research Facilities", "items": {"3.3.1": "Laboratories", "3.3.2": "Research Centers", "3.3.3": "Library Resources"}},
        "3.4": {"name": "Research Publications and Awards", "items": {"3.4.1": "Publications", "3.4.2": "Citations", "3.4.3": "Awards and Recognition"}},
        "3.5": {"name": "Consultancy", "items": {"3.5.1": "Consultancy Projects", "3.5.2": "Revenue Generated", "3.5.3": "Industry Partnerships"}},
        "3.6": {"name": "Extension Activities", "items": {"3.6.1": "Community Service", "3.6.2": "Outreach Programs", "3.6.3": "Social Responsibility"}},
        "3.7": {"name": "Collaboration", "items": {"3.7.1": "National Collaborations", "3.7.2": "International Collaborations", "3.7.3": "MoUs and Partnerships"}},
    },
    "Infrastructure & Learning Resources": {
        "4.1": {"name": "Physical Facilities", "items": {"4.1.1": "Classrooms", "4.1.2": "Laboratories", "4.1.3": "Seminar Halls", "4.1.4": "Hostel Facilities"}},
        "4.2": {"name": "Library as a Learning Resource", "items": {"4.2.1": "Library Collection", "4.2.2": "Digital Resources", "4.2.3": "Library Services"}},
        "4.3": {"name": "IT Infrastructure", "items": {"4.3.1": "Computer Facilities", "4.3.2": "Network Infrastructure", "4.3.3": "Software Resources"}},
        "4.4": {"name": "Maintenance of Campus Infrastructure", "items": {"4.4.1": "Maintenance Policy", "4.4.2": "Upgradation", "4.4.3": "Green Initiatives"}},
        "4.5": {"name": "Other Facilities", "items": {"4.5.1": "Sports Facilities", "4.5.2": "Health Services", "4.5.3": "Cafeteria"}},
    },
    "Student Support & Progression": {
        "5.1": {"name": "Student Mentoring and Support", "items": {"5.1.1": "Mentoring System", "5.1.2": "Counseling Services", "5.1.3": "Financial Support"}},
        "5.2": {"name": "Student Progression", "items": {"5.2.1": "Progression Rate", "5.2.2": "Placement", "5.2.3": "Higher Studies"}},
        "5.3": {"name": "Student Participation and Activities", "items": {"5.3.1": "Cultural Activities", "5.3.2": "Sports Activities", "5.3.3": "Technical Activities"}},
        "5.4": {"name": "Alumni Engagement", "items": {"5.4.1": "Alumni Association", "5.4.2": "Alumni Contribution", "5.4.3": "Alumni Network"}},
    },
    "Governance, Leadership & Management": {
        "6.1": {"name": "Institutional Vision and Leadership", "items": {"6.1.1": "Vision and Mission", "6.1.2": "Leadership", "6.1.3": "Strategic Planning"}},
        "6.2": {"name": "Strategy Development and Deployment", "items": {"6.2.1": "Strategic Plan", "6.2.2": "Implementation", "6.2.3": "Monitoring and Evaluation"}},
        "6.3": {"name": "Faculty Empowerment Strategies", "items": {"6.3.1": "Recruitment Policy", "6.3.2": "Professional Development", "6.3.3": "Performance Appraisal"}},
        "6.4": {"name": "Financial Management and Resource Mobilization", "items": {"6.4.1": "Budget Allocation", "6.4.2": "Resource Mobilization", "6.4.3": "Financial Audit"}},
        "6.5": {"name": "Internal Quality Assurance System", "items": {"6.5.1": "IQAC Structure", "6.5.2": "Quality Assurance Mechanisms", "6.5.3": "Quality Initiatives"}},
    },
    "Institutional Values & Best Practices": {
        "7.1": {"name": "Institutional Values and Social Responsibilities", "items": {"7.1.1": "Values and Ethics", "7.1.2": "Social Responsibility", "7.1.3": "Environmental Consciousness"}},
        "7.2": {"name": "Best Practices", "items": {"7.2.1": "Innovative Practices", "7.2.2": "Award Winning Practices", "7.2.3": "Replicable Practices"}},
        "7.3": {"name": "Institutional Distinctiveness", "items": {"7.3.1": "Unique Features", "7.3.2": "Special Achievements", "7.3.3": "Recognition"}},
    },
}


def _criteria_structure() -> List[Dict[str, Any]]:
    """Build API response: list of criteria with id, title, description, subFolders (each with id, title, items)."""
    out = []
    for idx, criterion_title in enumerate(CRITERION_ORDER, start=1):
        raw = NAAC_CRITERIA.get(criterion_title, {})
        subfolders = []
        for sub_id, sub_data in raw.items():
            items = [
                {"id": item_id, "title": item_title}
                for item_id, item_title in (sub_data.get("items") or {}).items()
            ]
            subfolders.append({
                "id": sub_id,
                "title": sub_data.get("name", sub_id),
                "items": items,
            })
        out.append({
            "id": idx,
            "title": criterion_title,
            "description": f"Documents and data for NAAC Criterion {idx}: {criterion_title}.",
            "subFolders": subfolders,
        })
    return out


@router.get("/criteria")
async def get_criteria(current_user: User = Depends(require_iqac)):
    """Return the full 7-criteria folder structure."""
    return _criteria_structure()


@router.get("/counts")
async def get_file_counts(current_user: User = Depends(require_iqac)):
    """Return file counts per criterion/subfolder/item for UI badges. Nested: { "1": { "1.1": { "1.1.1": 2, ... }, ... }, ... }."""
    counts: Dict[str, Any] = {}
    async for f in IQACFile.find(IQACFile.criterion <= 7, IQACFile.criterion >= 1):
        c, s, i = str(f.criterion), f.sub_folder, f.item
        if c not in counts:
            counts[c] = {}
        if s not in counts[c]:
            counts[c][s] = {}
        counts[c][s][i] = counts[c][s].get(i, 0) + 1
    return counts


@router.get("/ssr-sections", response_model=List[IQACSSRSectionResponse])
async def list_ssr_sections(current_user: User = Depends(require_iqac)):
    """Return all SSR/NAAC data-entry sections, including empty placeholders."""
    docs = await IQACSSRSection.find(
        {"section_key": {"$in": list(SSR_SECTION_KEYS)}}
    ).to_list()
    by_key = {doc.section_key: doc for doc in docs}
    return [_format_ssr_section(section_key, by_key.get(section_key)) for section_key in SSR_SECTION_KEYS]


@router.get("/ssr-sections/{section_key}", response_model=IQACSSRSectionResponse)
async def get_ssr_section(
    section_key: str,
    current_user: User = Depends(require_iqac),
):
    """Return one SSR/NAAC data-entry section."""
    normalized = _validate_ssr_section_key(section_key)
    doc = await IQACSSRSection.find_one(IQACSSRSection.section_key == normalized)
    return _format_ssr_section(normalized, doc)


@router.put("/ssr-sections/{section_key}", response_model=IQACSSRSectionResponse)
async def upsert_ssr_section(
    section_key: str,
    payload: IQACSSRSectionUpdate,
    current_user: User = Depends(require_iqac),
):
    """Create or update one SSR/NAAC data-entry section and record edit history."""
    normalized = _validate_ssr_section_key(section_key)
    now = datetime.utcnow()
    user_id = str(current_user.id)
    user_name = (current_user.name or "").strip()
    user_email = (current_user.email or "").strip()
    new_data = payload.data or {}

    await _purge_expired_ssr_history(now)

    doc = await IQACSSRSection.find_one(IQACSSRSection.section_key == normalized)
    previous_data = deepcopy(doc.data) if doc and doc.data else {}

    if _normalize_for_compare(previous_data) == _normalize_for_compare(new_data):
        return _format_ssr_section(
            normalized,
            doc,
            no_changes=True,
            message="No changes detected",
        )

    if not doc and not _has_meaningful_value(new_data):
        return _format_ssr_section(
            normalized,
            None,
            no_changes=True,
            message="No changes detected",
        )

    if doc:
        doc.data = new_data
        doc.updated_by = user_id
        doc.updated_by_name = user_name
        doc.updated_by_email = user_email
        doc.updated_at = now
        await doc.save()
    else:
        doc = IQACSSRSection(
            section_key=normalized,
            data=new_data,
            created_by=user_id,
            created_by_name=user_name,
            updated_by=user_id,
            updated_by_name=user_name,
            updated_by_email=user_email,
            created_at=now,
            updated_at=now,
        )
        await doc.insert()

    field_diffs = _compute_field_diffs(previous_data, new_data)
    changed_fields = sorted(field_diffs.keys())
    if not previous_data:
        change_summary = "First save"
    elif changed_fields:
        change_summary = "Modified: " + ", ".join(changed_fields)
    else:
        change_summary = "Saved"
    history_entry = IQACSSRHistory(
        section_key=normalized,
        previous_data=previous_data,
        new_data=new_data,
        changed_fields=changed_fields,
        field_diffs=field_diffs,
        change_summary=change_summary,
        edited_by=user_id,
        edited_by_user_id=user_id,
        edited_by_name=user_name,
        edited_by_email=user_email,
        edited_at=now,
        expires_at=now + timedelta(days=5),
    )
    await history_entry.insert()

    return _format_ssr_section(normalized, doc)


@router.get("/ssr-sections/{section_key}/history", response_model=List[IQACSSRHistoryResponse])
async def get_ssr_section_history(
    section_key: str,
    current_user: User = Depends(require_iqac),
):
    """Return edit history for an SSR section (entries from the last 5 days, newest first)."""
    normalized = _validate_ssr_section_key(section_key)
    now = datetime.utcnow()
    await _purge_expired_ssr_history(now)
    cutoff = now - timedelta(days=5)
    docs = await IQACSSRHistory.find(
        IQACSSRHistory.section_key == normalized,
        IQACSSRHistory.edited_at >= cutoff,
    ).sort(-IQACSSRHistory.edited_at).to_list()
    return [_serialize_ssr_history(history) for history in docs]


@router.get("/ssr-sections/{section_key}/history/{history_id}", response_model=IQACSSRHistoryResponse)
async def get_ssr_section_history_detail(
    section_key: str,
    history_id: str,
    current_user: User = Depends(require_iqac),
):
    """Return one SSR history entry with full previous/new data and field diffs."""
    normalized = _validate_ssr_section_key(section_key)
    now = datetime.utcnow()
    await _purge_expired_ssr_history(now)
    try:
        oid = PydanticObjectId(history_id)
    except Exception:
        raise HTTPException(status_code=404, detail="History entry not found")
    history = await IQACSSRHistory.get(oid)
    if not history or history.section_key != normalized:
        raise HTTPException(status_code=404, detail="History entry not found")
    if history.edited_at and history.edited_at < now - timedelta(days=5):
        raise HTTPException(status_code=404, detail="History entry not found")
    return _serialize_ssr_history(history)


@router.post("/ssr-sections/{section_key}/restore/{history_id}", response_model=IQACSSRSectionResponse)
async def restore_ssr_section_history(
    section_key: str,
    history_id: str,
    current_user: User = Depends(require_iqac),
):
    """Restore an SSR section to the version that existed before a selected edit."""
    normalized = _validate_ssr_section_key(section_key)
    now = datetime.utcnow()
    await _purge_expired_ssr_history(now)
    try:
        oid = PydanticObjectId(history_id)
    except Exception:
        raise HTTPException(status_code=404, detail="History entry not found")

    history = await IQACSSRHistory.get(oid)
    if not history or history.section_key != normalized:
        raise HTTPException(status_code=404, detail="History entry not found")

    user_id = str(current_user.id)
    user_name = (current_user.name or "").strip()
    user_email = (current_user.email or "").strip()
    restore_data = deepcopy(history.previous_data or {})
    doc = await IQACSSRSection.find_one(IQACSSRSection.section_key == normalized)
    previous_data = deepcopy(doc.data) if doc and doc.data else {}

    if _normalize_for_compare(previous_data) == _normalize_for_compare(restore_data):
        return _format_ssr_section(
            normalized,
            doc,
            no_changes=True,
            message="No changes detected",
        )

    if doc:
        doc.data = restore_data
        doc.updated_by = user_id
        doc.updated_by_name = user_name
        doc.updated_by_email = user_email
        doc.updated_at = now
        await doc.save()
    else:
        doc = IQACSSRSection(
            section_key=normalized,
            data=restore_data,
            created_by=user_id,
            created_by_name=user_name,
            updated_by=user_id,
            updated_by_name=user_name,
            updated_by_email=user_email,
            created_at=now,
            updated_at=now,
        )
        await doc.insert()

    field_diffs = _compute_field_diffs(previous_data, restore_data)
    changed_fields = sorted(field_diffs.keys())
    restored_at = history.edited_at.isoformat() if history.edited_at else str(history.id)
    history_entry = IQACSSRHistory(
        section_key=normalized,
        previous_data=previous_data,
        new_data=restore_data,
        changed_fields=changed_fields,
        field_diffs=field_diffs,
        change_summary=f"Restored version from {restored_at}",
        edited_by=user_id,
        edited_by_user_id=user_id,
        edited_by_name=user_name,
        edited_by_email=user_email,
        edited_at=now,
        expires_at=now + timedelta(days=5),
    )
    await history_entry.insert()

    return _format_ssr_section(normalized, doc, message="Version restored")


@router.get("/ssr-export/pdf")
async def export_ssr_pdf(current_user: User = Depends(require_iqac)):
    """Generate and download a NAAC SSR PDF document with all saved section data."""
    try:
        from ssr_pdf import generate_ssr_pdf
    except ImportError as exc:
        raise HTTPException(
            status_code=500,
            detail="PDF generation library (reportlab) is not installed. "
                   "Run: pip install reportlab",
        ) from exc

    # Fetch all four SSR sections
    docs = await IQACSSRSection.find(
        {"section_key": {"$in": list(SSR_SECTION_KEYS)}}
    ).to_list()
    by_key: dict[str, dict] = {doc.section_key: doc.data or {} for doc in docs}

    sections_data = {key: by_key.get(key, {}) for key in SSR_SECTION_KEYS}

    try:
        pdf_bytes = generate_ssr_pdf(
            sections_data,
            generated_by=current_user.email or getattr(current_user, "full_name", "") or "",
            generated_at=datetime.utcnow(),
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"PDF generation failed: {exc}") from exc

    filename = f"IQAC_SSR_NAAC_Report_{datetime.utcnow().strftime('%Y-%m-%d')}.pdf"
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.get("/ssr-export/docx")
async def export_ssr_docx(current_user: User = Depends(require_iqac)):
    """Generate and download a NAAC SSR Word (.docx) document with all saved section data."""
    try:
        from ssr_docx import generate_ssr_docx
    except ImportError as exc:
        raise HTTPException(
            status_code=500,
            detail="Word generation library (python-docx) is not installed. "
                   "Run: pip install python-docx",
        ) from exc

    docs = await IQACSSRSection.find(
        {"section_key": {"$in": list(SSR_SECTION_KEYS)}}
    ).to_list()
    by_key: dict[str, dict] = {doc.section_key: doc.data or {} for doc in docs}
    sections_data = {key: by_key.get(key, {}) for key in SSR_SECTION_KEYS}

    try:
        docx_bytes = generate_ssr_docx(
            sections_data,
            generated_by=current_user.email or getattr(current_user, "full_name", "") or "",
            generated_at=datetime.utcnow(),
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Word generation failed: {exc}") from exc

    filename = f"IQAC_SSR_NAAC_Report_{datetime.utcnow().strftime('%Y-%m-%d')}.docx"
    return Response(
        content=docx_bytes,
        media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.get("/templates")
async def list_templates(current_user: User = Depends(require_iqac)):
    """List predefined IQAC template documents available to authenticated IQAC users."""
    result = []
    for item in IQAC_TEMPLATE_DEFINITIONS:
        path = _resolve_template_file_path(item["file_name"])
        if not path:
            continue
        result.append({
            "id": item["id"],
            "name": item["name"],
            "fileName": item["file_name"],
            "type": item["type"],
            "size": os.path.getsize(path),
            "downloadUrl": f"/iqac/templates/{item['id']}/download",
        })
    return result


@router.get("/templates/{template_id}/download")
async def download_template(
    template_id: str,
    current_user: User = Depends(require_iqac),
):
    """Stream a predefined IQAC template document for authenticated users."""
    template = next((item for item in IQAC_TEMPLATE_DEFINITIONS if item["id"] == template_id), None)
    if not template:
        raise HTTPException(status_code=404, detail="Template not found")
    path = _resolve_template_file_path(template["file_name"])
    if not path:
        raise HTTPException(status_code=404, detail="Template file not found")
    return FileResponse(
        path,
        media_type=template["content_type"],
        filename=template["file_name"],
    )


def _safe_segment(name: str) -> str:
    """Allow only alphanumeric and dots for criterion/subfolder/item."""
    if not name or not re.match(r"^[\d.]+$", name):
        raise HTTPException(status_code=400, detail="Invalid segment")
    return name


def validate_iqac_path(criterion: int, subfolder: str, item: str) -> tuple[str, str]:
    """Return normalized sub_folder and item_id. Raises HTTPException if invalid."""
    if not 1 <= criterion <= 7:
        raise HTTPException(status_code=400, detail="Criterion must be 1-7")
    sub_folder = _safe_segment(subfolder.strip())
    item_id = _safe_segment(item.strip())
    title = CRITERION_ORDER[criterion - 1]
    raw = NAAC_CRITERIA.get(title, {})
    if sub_folder not in raw:
        raise HTTPException(status_code=400, detail="Invalid IQAC sub-criterion")
    items_dict = raw[sub_folder].get("items") or {}
    if item_id not in items_dict:
        raise HTTPException(status_code=400, detail="Invalid IQAC item")
    return sub_folder, item_id


@router.get("/folders/{criterion:int}/{subfolder}/{item}/files")
async def list_files(
    criterion: int,
    subfolder: str,
    item: str,
    current_user: User = Depends(require_iqac),
):
    """List files for a specific item (e.g. criterion=1, subfolder=1.1, item=1.1.1)."""
    if not 1 <= criterion <= 7:
        raise HTTPException(status_code=400, detail="Criterion must be 1-7")
    sub_folder = _safe_segment(subfolder.strip())
    item_id = _safe_segment(item.strip())
    files = await IQACFile.find(
        IQACFile.criterion == criterion,
        IQACFile.sub_folder == sub_folder,
        IQACFile.item == item_id,
    ).sort("-uploaded_at").to_list()
    result = []
    for f in files:
        uploaded_at = f.uploaded_at
        if uploaded_at and uploaded_at.tzinfo is None:
            uploaded_at = uploaded_at.replace(tzinfo=timezone.utc)
        result.append({
            "id": str(f.id),
            "criterion": f.criterion,
            "subFolder": f.sub_folder,
            "item": f.item,
            "fileName": f.file_name,
            "filePath": f.file_path,
            "uploadedBy": f.uploaded_by,
            "uploadedAt": uploaded_at.isoformat() if uploaded_at else None,
            "description": f.description or "",
            "size": f.size,
        })
    return result


def _allowed_filename(filename: str) -> tuple[bool, str]:
    if not filename:
        return False, "Missing filename"
    ext = os.path.splitext(filename)[1].lower()
    if ext not in ALLOWED_EXTENSIONS:
        return False, f"Allowed types: PDF, DOC, DOCX (got {ext})"
    return True, ""


def _allowed_file(file: UploadFile) -> tuple[bool, str]:
    return _allowed_filename(file.filename or "")


async def persist_iqac_upload(
    current_user: User,
    criterion: int,
    sub_folder: str,
    item_id: str,
    original_filename: str,
    content: bytes,
    description: str | None,
) -> dict:
    """Write IQAC file bytes to disk and insert IQACFile. Returns the same shape as the upload endpoint."""
    ok, err = _allowed_filename(original_filename)
    if not ok:
        raise HTTPException(status_code=400, detail=err)
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(status_code=400, detail="File size must not exceed 10MB")
    base_name = os.path.basename(original_filename) or "file"
    dir_path = os.path.join(IQAC_UPLOADS_DIR, str(criterion), sub_folder, item_id)
    try:
        os.makedirs(dir_path, exist_ok=True)
    except OSError as e:
        raise HTTPException(status_code=500, detail="Could not create upload directory") from e
    safe_name = f"{uuid.uuid4().hex}_{base_name}"
    file_path = os.path.join(dir_path, safe_name)
    try:
        with open(file_path, "wb") as out:
            out.write(content)
    except OSError as e:
        raise HTTPException(status_code=500, detail="Could not save file") from e
    relative_path = os.path.join("iqac", str(criterion), sub_folder, item_id, safe_name)
    doc = IQACFile(
        criterion=criterion,
        sub_folder=sub_folder,
        item=item_id,
        file_name=original_filename or safe_name,
        file_path=relative_path,
        uploaded_by=str(current_user.id),
        description=(description or "").strip() or None,
        size=len(content),
    )
    await doc.insert()
    uploaded_at = doc.uploaded_at
    if uploaded_at and uploaded_at.tzinfo is None:
        uploaded_at = uploaded_at.replace(tzinfo=timezone.utc)
    return {
        "id": str(doc.id),
        "criterion": doc.criterion,
        "subFolder": doc.sub_folder,
        "item": doc.item,
        "fileName": doc.file_name,
        "filePath": doc.file_path,
        "uploadedBy": doc.uploaded_by,
        "uploadedAt": uploaded_at.isoformat() if uploaded_at else None,
        "description": doc.description or "",
        "size": doc.size,
    }


@router.post("/folders/{criterion:int}/{subfolder}/{item}/files")
async def upload_file(
    criterion: int,
    subfolder: str,
    item: str,
    file: UploadFile = File(...),
    description: str = Form(""),
    current_user: User = Depends(require_iqac),
):
    """Upload a file for the given criterion/subfolder/item. Multipart form: file, optional description."""
    sub_folder, item_id = validate_iqac_path(criterion, subfolder, item)
    ok, err = _allowed_file(file)
    if not ok:
        raise HTTPException(status_code=400, detail=err)
    content = await file.read()
    return await persist_iqac_upload(
        current_user,
        criterion,
        sub_folder,
        item_id,
        file.filename or "file",
        content,
        (description or "").strip() or None,
    )


@router.delete("/files/{file_id}")
async def delete_file(
    file_id: str,
    current_user: User = Depends(require_iqac),
):
    """Delete file record and the stored file (not allowed for faculty)."""
    role = (current_user.role or "").strip().lower()
    if role not in IQAC_DELETE_ALLOWED_ROLES:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="IQAC file deletion is not allowed for your role",
        )
    from beanie import PydanticObjectId
    try:
        oid = PydanticObjectId(file_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid file id")
    doc = await IQACFile.get(oid)
    if not doc:
        raise HTTPException(status_code=404, detail="File not found")
    # Physical path: IQAC_UPLOADS_DIR is the base; doc.file_path is like iqac/1/1.1/1.1.1/xxx.pdf
    base = os.path.dirname(IQAC_UPLOADS_DIR)  # uploads
    abs_path = os.path.join(base, doc.file_path) if not os.path.isabs(doc.file_path) else doc.file_path
    if not os.path.normpath(abs_path).startswith(os.path.normpath(IQAC_UPLOADS_DIR)):
        abs_path = os.path.join(IQAC_UPLOADS_DIR, os.path.basename(doc.file_path))
    if os.path.isfile(abs_path):
        try:
            os.remove(abs_path)
        except OSError:
            pass
    await doc.delete()
    return {"ok": True}


def _resolve_file_path(doc: IQACFile) -> str:
    base = os.path.dirname(IQAC_UPLOADS_DIR)
    abs_path = os.path.join(base, doc.file_path) if not os.path.isabs(doc.file_path) else doc.file_path
    if not os.path.isfile(abs_path):
        abs_path = os.path.join(IQAC_UPLOADS_DIR, str(doc.criterion), doc.sub_folder, doc.item, os.path.basename(doc.file_path))
    return abs_path


@router.get("/files/{file_id}/download")
async def download_file(
    file_id: str,
    current_user: User = Depends(require_iqac),
):
    """Stream the file for download."""
    from beanie import PydanticObjectId
    try:
        oid = PydanticObjectId(file_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid file id")
    doc = await IQACFile.get(oid)
    if not doc:
        raise HTTPException(status_code=404, detail="File not found")
    path = _resolve_file_path(doc)
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="File not found on disk")
    return FileResponse(
        path,
        media_type="application/octet-stream",
        filename=doc.file_name,
    )
