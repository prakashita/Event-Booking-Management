import json
import os
from datetime import datetime

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Request, UploadFile, status

from rate_limit import limiter
from typing import Any, Dict, Literal, Optional

from auth import ensure_google_access_token
from drive import upload_report_file
from models import Publication, User
from routers.deps import get_current_user
from schemas import PaginatedResponse, PublicationResponse

router = APIRouter(prefix="/publications", tags=["Publications"])

DEFAULT_PUBLICATIONS_FOLDER_ID = "1Ad_30BIMiZSLxzyVvcCXcSi9zEMmPSw0"


def _format_contributor_item(item: Any) -> Optional[str]:
    if not isinstance(item, dict):
        return None
    if item.get("kind") == "organization":
        name = str(item.get("name") or item.get("organization") or item.get("screen_name") or item.get("screenName") or "").strip()
        return name or None
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


def _to_response(pub: Publication) -> PublicationResponse:
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

        try:
            access_token = await ensure_google_access_token(user)
            drive_file = upload_report_file(
                access_token=access_token,
                file_name=file.filename,
                file_bytes=contents,
                mime_type=file.content_type or "application/octet-stream",
                folder_id=folder_id,
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


@router.get("", response_model=PaginatedResponse[PublicationResponse])
async def list_publications(
    user: User = Depends(get_current_user),
    sort: Literal["title", "date"] = Query("date", description="Sort by title (A-Z) or date added"),
    order: Literal["asc", "desc"] = Query("desc", description="Sort order"),
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    offset: int = Query(0, ge=0),
):
    role = (user.role or "").strip().lower()
    if role in ("admin", "registrar", "vice_chancellor", "deputy_registrar", "finance_team"):
        query = Publication.find_all()
    else:
        query = Publication.find(Publication.created_by == str(user.id))

    sort_key = "-created_at" if sort == "date" and order == "desc" else "+created_at" if sort == "date" else "-title" if sort == "title" and order == "desc" else "+title"
    total = await query.count()
    items = await query.sort(sort_key).skip(offset).limit(limit).to_list()
    next_offset = offset + limit if offset + limit < total else None
    return PaginatedResponse[PublicationResponse](
        items=[_to_response(item) for item in items],
        total=total,
        limit=limit,
        offset=offset,
        next_offset=next_offset,
    )
