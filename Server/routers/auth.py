from fastapi import APIRouter
from pydantic import BaseModel
from models import User
from auth import verify_google_token, create_access_token

router = APIRouter(prefix="/auth", tags=["Auth"])


class TokenRequest(BaseModel):
    token: str


@router.post("/google")
async def google_login(payload: TokenRequest):
    google_data = verify_google_token(payload.token)

    google_id = google_data["sub"]
    email = google_data["email"]
    name = google_data.get("name", "")

    # Find user by google_id
    user = await User.find_one(User.google_id == google_id)

    if not user:
        # Create new user if doesn't exist
        user = User(
            name=name,
            email=email,
            google_id=google_id
        )
        await user.insert()

    jwt_token = create_access_token({"user_id": str(user.id)})

    return {
        "access_token": jwt_token,
        "user": {
            "id": str(user.id),
            "name": user.name,
            "email": user.email,
            "role": user.role
        }
    }
