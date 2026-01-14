from sqlalchemy import Column, Integer, String, DateTime
from datetime import datetime
from database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String)
    email = Column(String, unique=True, index=True)
    google_id = Column(String, unique=True)
    role = Column(String, default="faculty")
    created_at = Column(DateTime, default=datetime.utcnow)
