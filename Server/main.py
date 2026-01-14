from fastapi import FastAPI
from database import engine
import models
from routers import auth

models.Base.metadata.create_all(bind=engine)

app = FastAPI()

app.include_router(auth.router)

@app.get("/")
def home():
    return {"message": "Backend running"}
