from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from core.config import settings
from api import auth, dashboard, manual_inputs, chat
from db.database import engine, Base
import db.models  # Ensure models are registered with Base.metadata

app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
)

@app.on_event("startup")
async def startup_event():
    print("Backend is starting up...")
    # Create tables if they don't exist
    Base.metadata.create_all(bind=engine)
    print("Database tables synchronized.")
    for route in app.routes:
        print(f"Registered route: {route.path}")

# CORS middleware for local development / app connections
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include Routers
app.include_router(auth.router, prefix="/api/auth", tags=["auth"])
app.include_router(dashboard.router, prefix="/api/dashboard", tags=["dashboard"])
app.include_router(manual_inputs.router, prefix="/api/manual_inputs", tags=["manual_inputs"])
app.include_router(chat.router, prefix="/api/chat", tags=["chat"])

@app.get("/")
def read_root():
    return {"message": "Welcome to TA WatchDog API"}
