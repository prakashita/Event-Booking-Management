from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session
from database import SessionLocal
from models import User
from auth import verify_google_token, create_access_token

router = APIRouter(prefix="/auth", tags=["Auth"])


class TokenRequest(BaseModel):
    token: str


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


@router.post("/google")
def google_login(payload: TokenRequest, db: Session = Depends(get_db)):
    google_data = verify_google_token(payload.token)

    google_id = google_data["sub"]
    email = google_data["email"]
    name = google_data.get("name", "")

    user = db.query(User).filter(User.google_id == google_id).first()

    if not user:
        user = User(name=name, email=email, google_id=google_id)
        db.add(user)
        db.commit()
        db.refresh(user)

    jwt_token = create_access_token({"user_id": user.id})

    return {
        "access_token": jwt_token,
        "user": {
            "id": user.id,
            "name": user.name,
            "email": user.email
        }
    }
