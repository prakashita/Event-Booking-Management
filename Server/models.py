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
    
    class Settings:
        name = "users"  # Collection name in MongoDB
        indexes = [
            "email",
            "google_id"
        ]
