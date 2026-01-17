from beanie import Document
from pydantic import Field
from datetime import datetime
from typing import Optional

class User(Document):
    name: str
    email: str = Field(unique=True)
    google_id: str = Field(unique=True)
    role: str = Field(default="faculty")
    created_at: datetime = Field(default_factory=datetime.utcnow)
    google_refresh_token: Optional[str] = None
    google_access_token: Optional[str] = None
    google_token_expiry: Optional[datetime] = None
    
    class Settings:
        name = "users"  # Collection name in MongoDB
        indexes = [
            "email",
            "google_id"
        ]
