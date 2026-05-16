import json
import os
from datetime import datetime

from bson import ObjectId
from bson.errors import InvalidId
from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Request, UploadFile, status

from rate_limit import limiter
from typing import Any, Dict, List, Literal, Optional

from auth import ensure_google_access_token
from drive import sanitize_folder_name, upload_file_to_nested_folder, upload_report_file
from models import Publication, User
from routers.deps import get_current_user
from schemas import PaginatedResponse, PublicationResponse

router = APIRouter(prefix="/publications", tags=["Publications"])

DEFAULT_PUBLICATIONS_FOLDER_ID = "1Ad_30BIMiZSLxzyVvcCXcSi9zEMmPSw0"


def _format_contributor_item(item: Any) -> Optional[str]:
    if not isinstance(item, dict):
        return None
    # New schema: type="organization"|"person", with nested dicts
    item_type = item.get("type") or item.get("kind")
    if item_type == "organization":
        org = item.get("organization") or {}
        if isinstance(org, dict):
            name = str(org.get("name") or org.get("screen_name") or "").strip()
            if name:
                return name
        # Fallback: old flat schema
        name = str(item.get("name") or item.get("screen_name") or item.get("screenName") or "").strip()
        return name or None
    # Person (default when type is absent or "person")
    person = item.get("person") or {}
    if isinstance(person, dict):
        name = " ".join(
            str(person.get(key) or "").strip()
            for key in ("title", "initials", "first_names", "infix", "last_name", "suffix")
            if str(person.get(key) or "").strip()
        )
        screen_name = str(person.get("screen_name") or "").strip()
        if name or screen_name:
            return name or screen_name
    # Fallback: old flat schema with direct fields
    name = " ".join(
        str(item.get(key) or "").strip()
        for key in ("title", "initials", "first_name", "first_names", "infix", "last_name", "suffix")
        if str(item.get(key) or "").strip()
    )
    screen_name = str(item.get("screen_name") or item.get("screenName") or "").strip()
    return name or screen_name or None


def _format_contributors(value: Any) -> Optional[str]:
    if isinstance(value, list):
        label = "; ".join(part for part in (_format_contributor_item(item) for item in value) if part)
        return label or None
    if isinstance(value, str):
        raw = value.strip()
        if not raw:
            return None
        try:
            parsed = json.loads(raw)
            parsed_label = _format_contributors(parsed)
            if parsed_label:
                return parsed_label
        except Exception:
            pass
        return raw
    return None


def _to_response(
    pub: Publication,
    creator_info: Optional[Dict[str, str]] = None,
    updater_info: Optional[Dict[str, str]] = None,
) -> PublicationResponse:
    # Prefer name stored on the document; fall back to externally resolved info (for old records)
    c_name = getattr(pub, "created_by_name", None) or (creator_info or {}).get("name") or None
    c_email = getattr(pub, "created_by_email", None) or (creator_info or {}).get("email") or None
    u_name = getattr(pub, "updated_by_name", None) or (updater_info or {}).get("name") or None
    u_email = getattr(pub, "updated_by_email", None) or (updater_info or {}).get("email") or None
    return PublicationResponse(
        id=str(pub.id),
        name=pub.name,
        title=pub.title,
        pub_type=pub.pub_type,
        source_type=getattr(pub, "source_type", None) or pub.pub_type,
        citation_format=getattr(pub, "citation_format", None),
        details=getattr(pub, "details", None) or {},
        others=pub.others,
        file_id=pub.file_id,
        file_name=pub.file_name,
        web_view_link=pub.web_view_link,
        uploaded_at=pub.uploaded_at,
        created_at=pub.created_at,
        created_by=pub.created_by,
        created_by_name=c_name,
        created_by_email=c_email,
        updated_by=getattr(pub, "updated_by", None),
        updated_by_name=u_name,
        updated_by_email=u_email,
        updated_at=getattr(pub, "updated_at", None),
        author=pub.author,
        author_first_name=getattr(pub, "author_first_name", None),
        author_last_name=getattr(pub, "author_last_name", None),
        publication_date=pub.publication_date,
        issued_date=getattr(pub, "issued_date", None),
        accessed_date=getattr(pub, "accessed_date", None),
        composed_date=getattr(pub, "composed_date", None),
        submitted_date=getattr(pub, "submitted_date", None),
        content=getattr(pub, "content", None),
        contributors=getattr(pub, "contributors", None),
        container_title=getattr(pub, "container_title", None),
        collection_title=getattr(pub, "collection_title", None),
        note=getattr(pub, "note", None),
        source=getattr(pub, "source", None),
        url=pub.url,
        pdf_url=getattr(pub, "pdf_url", None),
        article_title=pub.article_title,
        journal_name=pub.journal_name,
        volume=pub.volume,
        issue=pub.issue,
        pages=pub.pages,
        doi=pub.doi,
        year=pub.year,
        book_title=pub.book_title,
        publisher=pub.publisher,
        edition=pub.edition,
        page_number=pub.page_number,
        organization=pub.organization,
        report_title=pub.report_title,
        creator=pub.creator,
        video_title=pub.video_title,
        platform=pub.platform,
        newspaper_name=pub.newspaper_name,
        website_name=pub.website_name,
        page_title=pub.page_title,
    )


@router.post("", response_model=PublicationResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit("30/minute")
async def upload_publication(
    request: Request,
    name: str = Form(...),
    title: str = Form(...),
    pub_type: str = Form(...),
    source_type: Optional[str] = Form(default=None),
    citation_format: Optional[str] = Form(default=None),
    details: Optional[str] = Form(default=None),
    others: Optional[str] = Form(default=None),
    file: Optional[UploadFile] = File(default=None),
    # Shared
    author: Optional[str] = Form(default=None),
    author_first_name: Optional[str] = Form(default=None),
    author_last_name: Optional[str] = Form(default=None),
    publication_date: Optional[str] = Form(default=None),
    issued_date: Optional[str] = Form(default=None),
    accessed_date: Optional[str] = Form(default=None),
    composed_date: Optional[str] = Form(default=None),
    submitted_date: Optional[str] = Form(default=None),
    content: Optional[str] = Form(default=None),
    contributors: Optional[str] = Form(default=None),
    container_title: Optional[str] = Form(default=None),
    collection_title: Optional[str] = Form(default=None),
    note: Optional[str] = Form(default=None),
    source: Optional[str] = Form(default=None),
    url: Optional[str] = Form(default=None),
    pdf_url: Optional[str] = Form(default=None),
    # Journal Article
    article_title: Optional[str] = Form(default=None),
    journal_name: Optional[str] = Form(default=None),
    volume: Optional[str] = Form(default=None),
    issue: Optional[str] = Form(default=None),
    pages: Optional[str] = Form(default=None),
    doi: Optional[str] = Form(default=None),
    year: Optional[str] = Form(default=None),
    # Book
    book_title: Optional[str] = Form(default=None),
    publisher: Optional[str] = Form(default=None),
    edition: Optional[str] = Form(default=None),
    page_number: Optional[str] = Form(default=None),
    # Report
    organization: Optional[str] = Form(default=None),
    report_title: Optional[str] = Form(default=None),
    # Video
    creator: Optional[str] = Form(default=None),
    video_title: Optional[str] = Form(default=None),
    platform: Optional[str] = Form(default=None),
    # Online Newspaper / Webpage
    newspaper_name: Optional[str] = Form(default=None),
    website_name: Optional[str] = Form(default=None),
    page_title: Optional[str] = Form(default=None),
    user: User = Depends(get_current_user),
):
    detail_payload: Dict[str, Any] = {}
    if details:
        try:
            parsed_details = json.loads(details)
            if not isinstance(parsed_details, dict):
                raise ValueError("details must be an object")
            detail_payload = parsed_details
        except Exception:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid publication details payload")

    if contributors:
        try:
            parsed_contributors = json.loads(contributors)
            detail_payload["contributors"] = parsed_contributors if isinstance(parsed_contributors, list) else contributors
        except Exception:
            detail_payload["contributors"] = contributors

    detail_payload.update(
        {
            key: value
            for key, value in {
                "issued_date": issued_date,
                "accessed_date": accessed_date,
                "composed_date": composed_date,
                "submitted_date": submitted_date,
                "content": content,
                "container_title": container_title,
                "collection_title": collection_title,
                "note": note,
                "source": source,
                "url": url,
                "pdf_url": pdf_url,
                "doi": doi,
                "publisher": publisher,
            }.items()
            if value
        }
    )
    contributors_display = _format_contributors(contributors) or _format_contributors(detail_payload.get("contributors"))

    file_id = None
    file_name = None
    web_view_link = None
    uploaded_at = None

    if file and file.filename:
        contents = await file.read()
        max_size = 10 * 1024 * 1024
        if len(contents) > max_size:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="File too large (max 10MB)")

        folder_id = os.getenv("PUBLICATIONS_DRIVE_FOLDER_ID", DEFAULT_PUBLICATIONS_FOLDER_ID)
        if not folder_id:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Google Drive folder not configured",
            )

        # Build nested folder path: Publication-Uploads / YYYY / YYYY-MM / Title
        try:
            _pub_date_raw = (publication_date or issued_date or "").strip()
            _pdt = datetime.strptime(_pub_date_raw[:10], "%Y-%m-%d") if len(_pub_date_raw) >= 10 else None
        except Exception:
            _pdt = None
        if _pdt is None and year:
            try:
                _pdt = datetime.strptime(str(year).strip()[:4], "%Y")
            except Exception:
                pass
        if _pdt is None:
            _pdt = datetime.utcnow()
        _pub_folder_parts = [
            "Publication-Uploads",
            _pdt.strftime("%Y"),
            _pdt.strftime("%Y-%m"),
            sanitize_folder_name(title or name or "Publication"),
        ]

        try:
            access_token = await ensure_google_access_token(user)
            drive_file = upload_file_to_nested_folder(
                access_token=access_token,
                file_name=file.filename,
                file_bytes=contents,
                mime_type=file.content_type or "application/octet-stream",
                root_folder_id=folder_id,
                folder_path_parts=_pub_folder_parts,
            )
            file_id = drive_file.get("id", "")
            file_name = drive_file.get("name", file.filename)
            web_view_link = drive_file.get("webViewLink")
            uploaded_at = datetime.utcnow()
        except RuntimeError as exc:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=str(exc),
            )
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Unable to upload publication: {exc}",
            )

    publication = Publication(
        name=name,
        title=title,
        pub_type=pub_type,
        source_type=source_type or pub_type,
        citation_format=citation_format,
        details=detail_payload,
        others=others,
        file_id=file_id,
        file_name=file_name,
        web_view_link=web_view_link,
        uploaded_at=uploaded_at,
        created_by=str(user.id),
        created_by_name=user.name or None,
        created_by_email=user.email or None,
        author=(author or contributors_display or " ".join([(author_first_name or "").strip(), (author_last_name or "").strip()]).strip() or None),
        author_first_name=author_first_name,
        author_last_name=author_last_name,
        publication_date=publication_date,
        issued_date=issued_date or detail_payload.get("issued_date"),
        accessed_date=accessed_date or detail_payload.get("accessed_date"),
        composed_date=composed_date or detail_payload.get("composed_date"),
        submitted_date=submitted_date or detail_payload.get("submitted_date"),
        content=content or detail_payload.get("content"),
        contributors=contributors_display,
        container_title=container_title or detail_payload.get("container_title"),
        collection_title=collection_title or detail_payload.get("collection_title"),
        note=note or detail_payload.get("note"),
        source=source or detail_payload.get("source"),
        url=url,
        pdf_url=pdf_url or detail_payload.get("pdf_url"),
        article_title=article_title,
        journal_name=journal_name,
        volume=volume,
        issue=issue,
        pages=pages,
        doi=doi,
        year=year,
        book_title=book_title,
        publisher=publisher,
        edition=edition,
        page_number=page_number,
        organization=organization,
        report_title=report_title,
        creator=creator,
        video_title=video_title,
        platform=platform,
        newspaper_name=newspaper_name,
        website_name=website_name,
        page_title=page_title,
    )
    await publication.insert()

    return _to_response(publication)


DEFAULT_LIMIT = 50
MAX_LIMIT = 100


async def _bulk_user_info(user_ids: List[str]) -> Dict[str, Dict[str, str]]:
    """Return {user_id_str: {"name": ..., "email": ...}} via raw Motor query (avoids Beanie operator issues)."""
    if not user_ids:
        return {}
    oid_map: Dict[str, ObjectId] = {}
    for uid in set(uid for uid in user_ids if uid):
        try:
            oid_map[uid] = ObjectId(uid)
        except (InvalidId, TypeError):
            pass
    if not oid_map:
        return {}
    result: Dict[str, Dict[str, str]] = {}
    try:
        collection = User.get_motor_collection()
        docs = await collection.find({"_id": {"$in": list(oid_map.values())}}).to_list(None)
        for doc in docs:
            uid_str = str(doc["_id"])
            result[uid_str] = {"name": doc.get("name") or "", "email": doc.get("email") or ""}
    except Exception:
        pass
    return result


@router.get("", response_model=PaginatedResponse[PublicationResponse])
async def list_publications(
    user: User = Depends(get_current_user),
    sort: Literal["title", "date"] = Query("date", description="Sort by title (A-Z) or date added"),
    order: Literal["asc", "desc"] = Query("desc", description="Sort order"),
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    offset: int = Query(0, ge=0),
):
    role = (user.role or "").strip().lower()
    # Only admin role sees all publications; every other role sees their own only.
    if role == "admin":
        query = Publication.find_all()
    else:
        query = Publication.find(Publication.created_by == str(user.id))

    sort_key = "-created_at" if sort == "date" and order == "desc" else "+created_at" if sort == "date" else "-title" if sort == "title" and order == "desc" else "+title"
    total = await query.count()
    items = await query.sort(sort_key).skip(offset).limit(limit).to_list()
    next_offset = offset + limit if offset + limit < total else None
    # Resolve creator info for old records that don't have the name stored on the document.
    missing_ids = [p.created_by for p in items if p.created_by and not getattr(p, "created_by_name", None)]
    info_map = await _bulk_user_info(missing_ids) if missing_ids else {}
    return PaginatedResponse[PublicationResponse](
        items=[
            _to_response(item, info_map.get(item.created_by) if not getattr(item, "created_by_name", None) else None)
            for item in items
        ],
        total=total,
        limit=limit,
        offset=offset,
        next_offset=next_offset,
    )


@router.get("/{publication_id}", response_model=PublicationResponse)
async def get_publication(
    publication_id: str,
    user: User = Depends(get_current_user),
):
    try:
        oid = ObjectId(publication_id)
    except (InvalidId, TypeError):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Publication not found.")
    pub = await Publication.find_one(Publication.id == oid)
    if pub is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Publication not found.")
    role = (user.role or "").strip().lower()
    is_admin = role == "admin"
    if not is_admin and pub.created_by != str(user.id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied.")
    # Resolve any missing creator/updater info for old records.
    missing_ids = [uid for uid in [pub.created_by if not getattr(pub, "created_by_name", None) else None,
                                    getattr(pub, "updated_by", None) if not getattr(pub, "updated_by_name", None) else None] if uid]
    info_map = await _bulk_user_info(missing_ids) if missing_ids else {}
    creator_info = info_map.get(pub.created_by) if not getattr(pub, "created_by_name", None) else None
    updater_id = getattr(pub, "updated_by", None)
    updater_info = info_map.get(updater_id) if (updater_id and not getattr(pub, "updated_by_name", None)) else None
    return _to_response(pub, creator_info, updater_info)


@router.patch("/{publication_id}", response_model=PublicationResponse)
@limiter.limit("30/minute")
async def update_publication(
    request: Request,
    publication_id: str,
    name: Optional[str] = Form(default=None),
    title: Optional[str] = Form(default=None),
    pub_type: Optional[str] = Form(default=None),
    source_type: Optional[str] = Form(default=None),
    citation_format: Optional[str] = Form(default=None),
    details: Optional[str] = Form(default=None),
    others: Optional[str] = Form(default=None),
    author: Optional[str] = Form(default=None),
    author_first_name: Optional[str] = Form(default=None),
    author_last_name: Optional[str] = Form(default=None),
    publication_date: Optional[str] = Form(default=None),
    issued_date: Optional[str] = Form(default=None),
    accessed_date: Optional[str] = Form(default=None),
    composed_date: Optional[str] = Form(default=None),
    submitted_date: Optional[str] = Form(default=None),
    content: Optional[str] = Form(default=None),
    contributors: Optional[str] = Form(default=None),
    container_title: Optional[str] = Form(default=None),
    collection_title: Optional[str] = Form(default=None),
    note: Optional[str] = Form(default=None),
    source: Optional[str] = Form(default=None),
    url: Optional[str] = Form(default=None),
    pdf_url: Optional[str] = Form(default=None),
    article_title: Optional[str] = Form(default=None),
    journal_name: Optional[str] = Form(default=None),
    volume: Optional[str] = Form(default=None),
    issue: Optional[str] = Form(default=None),
    pages: Optional[str] = Form(default=None),
    doi: Optional[str] = Form(default=None),
    year: Optional[str] = Form(default=None),
    book_title: Optional[str] = Form(default=None),
    publisher: Optional[str] = Form(default=None),
    edition: Optional[str] = Form(default=None),
    page_number: Optional[str] = Form(default=None),
    organization: Optional[str] = Form(default=None),
    report_title: Optional[str] = Form(default=None),
    creator: Optional[str] = Form(default=None),
    video_title: Optional[str] = Form(default=None),
    platform: Optional[str] = Form(default=None),
    newspaper_name: Optional[str] = Form(default=None),
    website_name: Optional[str] = Form(default=None),
    page_title: Optional[str] = Form(default=None),
    user: User = Depends(get_current_user),
):
    try:
        oid = ObjectId(publication_id)
    except (InvalidId, TypeError):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Publication not found.")
    pub = await Publication.find_one(Publication.id == oid)
    if pub is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Publication not found.")
    role = (user.role or "").strip().lower()
    is_admin = role == "admin"
    # Admin cannot edit; only the creator/owner can edit.
    if is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin users cannot edit publications.")
    if pub.created_by != str(user.id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the creator can edit this publication.")

    detail_payload: Dict[str, Any] = dict(pub.details or {})
    if details:
        try:
            parsed = json.loads(details)
            if isinstance(parsed, dict):
                detail_payload.update(parsed)
        except Exception:
            pass
    for key, value in {
        "issued_date": issued_date, "accessed_date": accessed_date,
        "composed_date": composed_date, "submitted_date": submitted_date,
        "content": content, "container_title": container_title,
        "collection_title": collection_title, "note": note,
        "source": source, "url": url, "pdf_url": pdf_url, "doi": doi,
        "publisher": publisher,
    }.items():
        if value is not None:
            detail_payload[key] = value

    update_fields: Dict[str, Any] = {"details": detail_payload}
    if name is not None: update_fields["name"] = name
    if title is not None: update_fields["title"] = title
    if pub_type is not None: update_fields["pub_type"] = pub_type
    if source_type is not None: update_fields["source_type"] = source_type
    if citation_format is not None: update_fields["citation_format"] = citation_format
    if others is not None: update_fields["others"] = others
    if author is not None: update_fields["author"] = author
    if author_first_name is not None: update_fields["author_first_name"] = author_first_name
    if author_last_name is not None: update_fields["author_last_name"] = author_last_name
    if publication_date is not None: update_fields["publication_date"] = publication_date
    if issued_date is not None: update_fields["issued_date"] = issued_date
    if accessed_date is not None: update_fields["accessed_date"] = accessed_date
    if composed_date is not None: update_fields["composed_date"] = composed_date
    if submitted_date is not None: update_fields["submitted_date"] = submitted_date
    if content is not None: update_fields["content"] = content
    if contributors is not None:
        formatted = _format_contributors(contributors)
        # Preserve structured array in detail_payload for future edits
        try:
            parsed_contrib = json.loads(contributors)
            if isinstance(parsed_contrib, list):
                detail_payload["contributors"] = parsed_contrib
        except Exception:
            pass
        update_fields["contributors"] = formatted
        # Keep pub.author in sync with the new contributors when no manual
        # author override was sent — cards read item.author, not item.contributors.
        if author is None and formatted:
            update_fields["author"] = formatted
    if container_title is not None: update_fields["container_title"] = container_title
    if collection_title is not None: update_fields["collection_title"] = collection_title
    if note is not None: update_fields["note"] = note
    if source is not None: update_fields["source"] = source
    if url is not None: update_fields["url"] = url
    if pdf_url is not None: update_fields["pdf_url"] = pdf_url
    if article_title is not None: update_fields["article_title"] = article_title
    if journal_name is not None: update_fields["journal_name"] = journal_name
    if volume is not None: update_fields["volume"] = volume
    if issue is not None: update_fields["issue"] = issue
    if pages is not None: update_fields["pages"] = pages
    if doi is not None: update_fields["doi"] = doi
    if year is not None: update_fields["year"] = year
    if book_title is not None: update_fields["book_title"] = book_title
    if publisher is not None: update_fields["publisher"] = publisher
    if edition is not None: update_fields["edition"] = edition
    if page_number is not None: update_fields["page_number"] = page_number
    if organization is not None: update_fields["organization"] = organization
    if report_title is not None: update_fields["report_title"] = report_title
    if creator is not None: update_fields["creator"] = creator
    if video_title is not None: update_fields["video_title"] = video_title
    if platform is not None: update_fields["platform"] = platform
    if newspaper_name is not None: update_fields["newspaper_name"] = newspaper_name
    if website_name is not None: update_fields["website_name"] = website_name
    if page_title is not None: update_fields["page_title"] = page_title

    update_fields["updated_by"] = str(user.id)
    update_fields["updated_by_name"] = user.name or None
    update_fields["updated_by_email"] = user.email or None
    update_fields["updated_at"] = datetime.utcnow()
    await pub.set(update_fields)
    # Apply to in-memory object so _to_response reads updated values.
    for _k, _v in update_fields.items():
        try:
            setattr(pub, _k, _v)
        except Exception:
            pass
    return _to_response(pub)


@router.delete("/{publication_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_publication(
    publication_id: str,
    user: User = Depends(get_current_user),
):
    try:
        oid = ObjectId(publication_id)
    except (InvalidId, TypeError):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Publication not found.")
    pub = await Publication.find_one(Publication.id == oid)
    if pub is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Publication not found.")
    role = (user.role or "").strip().lower()
    is_admin = role == "admin"
    if not is_admin and pub.created_by != str(user.id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied.")
    await pub.delete()
