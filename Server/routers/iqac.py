"""
IQAC Data Collection API: criteria tree, file list/upload/delete/download.
Access restricted to users with IQAC (or admin/registrar) role.
"""
import os
import re
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, List

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from fastapi.responses import FileResponse

from models import IQACFile, User
from routers.deps import require_iqac

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


# NAAC IQAC 7-criteria structure: criterion title → sub-criteria (1.1, 1.2, …) → items (1.1.1, 1.1.2, …)
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
    criterion_order = [
        "Curricular Aspects",
        "Teaching-Learning & Evaluation",
        "Research, Innovations & Extension",
        "Infrastructure & Learning Resources",
        "Student Support & Progression",
        "Governance, Leadership & Management",
        "Institutional Values & Best Practices",
    ]
    out = []
    for idx, criterion_title in enumerate(criterion_order, start=1):
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


def _safe_segment(name: str) -> str:
    """Allow only alphanumeric and dots for criterion/subfolder/item."""
    if not name or not re.match(r"^[\d.]+$", name):
        raise HTTPException(status_code=400, detail="Invalid segment")
    return name


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


def _allowed_file(file: UploadFile) -> tuple[bool, str]:
    if not file.filename:
        return False, "Missing filename"
    ext = os.path.splitext(file.filename)[1].lower()
    if ext not in ALLOWED_EXTENSIONS:
        return False, f"Allowed types: PDF, DOC, DOCX (got {ext})"
    return True, ""


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
    if not 1 <= criterion <= 7:
        raise HTTPException(status_code=400, detail="Criterion must be 1-7")
    sub_folder = _safe_segment(subfolder.strip())
    item_id = _safe_segment(item.strip())
    ok, err = _allowed_file(file)
    if not ok:
        raise HTTPException(status_code=400, detail=err)
    content = await file.read()
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(status_code=400, detail="File size must not exceed 10MB")
    dir_path = os.path.join(IQAC_UPLOADS_DIR, str(criterion), sub_folder, item_id)
    try:
        os.makedirs(dir_path, exist_ok=True)
    except OSError as e:
        raise HTTPException(status_code=500, detail="Could not create upload directory") from e
    safe_name = f"{uuid.uuid4().hex}_{file.filename}"
    file_path = os.path.join(dir_path, safe_name)
    try:
        with open(file_path, "wb") as out:
            out.write(content)
    except OSError as e:
        raise HTTPException(status_code=500, detail="Could not save file") from e
    # Store relative path from IQAC_UPLOADS_DIR for portability
    relative_path = os.path.join("iqac", str(criterion), sub_folder, item_id, safe_name)
    doc = IQACFile(
        criterion=criterion,
        sub_folder=sub_folder,
        item=item_id,
        file_name=file.filename or safe_name,
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


@router.delete("/files/{file_id}")
async def delete_file(
    file_id: str,
    current_user: User = Depends(require_iqac),
):
    """Delete file record and the stored file."""
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
