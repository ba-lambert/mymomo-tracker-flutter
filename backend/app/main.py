from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .database import Base, engine
from .routers import dashboard, messages, phones, pull_requests

Base.metadata.create_all(bind=engine)

app = FastAPI(title="MoMo Tracker Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount("/static", StaticFiles(directory="app/static"), name="static")

app.include_router(phones.router)
app.include_router(messages.router)
app.include_router(dashboard.router)
app.include_router(pull_requests.router)
