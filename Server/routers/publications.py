import os
from datetime import datetime

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status, Form
from typing import Optional

from auth import ensure_google_access_token
from drive import upload_report_file
from models import Publication, User
from routers.deps import get_current_user
from schemas import PublicationResponse

router = APIRouter(prefix="/publications", tags=["Publications"])

DEFAULT_PUBLICATIONS_FOLDER_ID = "1Ad_30BIMiZSLxzyVvcCXcSi9zEMmPSw0"


def _to_response(pub: Publication) -> PublicationResponse:
    return PublicationResponse(
        id=str(pub.id),
        name=pub.name,
        title=pub.title,
        pub_type=pub.pub_type,
        others=pub.others,
        file_id=pub.file_id,
        file_name=pub.file_name,
        web_view_link=pub.web_view_link,
        uploaded_at=pub.uploaded_at,
        created_at=pub.created_at,
        author=pub.author,
        publication_date=pub.publication_date,
        url=pub.url,
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
async def upload_publication(
    name: str = Form(...),
    title: str = Form(...),
    pub_type: str = Form(...),
    others: Optional[str] = Form(default=None),
    file: Optional[UploadFile] = File(default=None),
    # Shared
    author: Optional[str] = Form(default=None),
    publication_date: Optional[str] = Form(default=None),
    url: Optional[str] = Form(default=None),
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
        others=others,
        file_id=file_id,
        file_name=file_name,
        web_view_link=web_view_link,
        uploaded_at=uploaded_at,
        created_by=str(user.id),
        author=author,
        publication_date=publication_date,
        url=url,
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


@router.get("", response_model=list[PublicationResponse])
async def list_publications(user: User = Depends(get_current_user)):
    items = await Publication.find_all().sort("-created_at").to_list()
    return [_to_response(item) for item in items]
