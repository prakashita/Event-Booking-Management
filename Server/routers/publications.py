import os
from datetime import datetime

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status, Form

from auth import ensure_google_access_token
from drive import upload_report_file
from models import Publication, User
from routers.deps import get_current_user
from schemas import PublicationResponse

router = APIRouter(prefix="/publications", tags=["Publications"])

DEFAULT_PUBLICATIONS_FOLDER_ID = "1Ad_30BIMiZSLxzyVvcCXcSi9zEMmPSw0"


@router.post("", response_model=PublicationResponse, status_code=status.HTTP_201_CREATED)
async def upload_publication(
    name: str = Form(...),
    title: str = Form(...),
    others: str | None = Form(default=None),
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
):
    if not file.filename:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Missing file")

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
        others=others,
        file_id=drive_file.get("id", ""),
        file_name=drive_file.get("name", file.filename),
        web_view_link=drive_file.get("webViewLink"),
        uploaded_at=datetime.utcnow(),
        created_by=str(user.id),
    )
    await publication.insert()

    return PublicationResponse(
        id=str(publication.id),
        name=publication.name,
        title=publication.title,
        others=publication.others,
        file_id=publication.file_id,
        file_name=publication.file_name,
        web_view_link=publication.web_view_link,
        uploaded_at=publication.uploaded_at,
        created_at=publication.created_at,
    )


@router.get("", response_model=list[PublicationResponse])
async def list_publications(user: User = Depends(get_current_user)):
    items = await Publication.find_all().sort("-created_at").to_list()
    return [
        PublicationResponse(
            id=str(item.id),
            name=item.name,
            title=item.title,
            others=item.others,
            file_id=item.file_id,
            file_name=item.file_name,
            web_view_link=item.web_view_link,
            uploaded_at=item.uploaded_at,
            created_at=item.created_at,
        )
        for item in items
    ]
