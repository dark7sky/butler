import os
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    PROJECT_NAME: str = "TA WatchDog API"
    VERSION: str = "1.0.0"

    SECRET_KEY: str = os.environ.get(
        "SECRET_KEY", "your-super-secret-key-change-it-in-production"
    )
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7

    MASTER_PASSWORD: str = os.environ.get("MASTER_PASSWORD", "admin")

    DATABASE_URL: str = os.environ.get(
        "DATABASE_URL", "postgresql://postgres:password@localhost:5432/postgres"
    )
    KEY_OPENAI: str | None = os.environ.get("KEY_OPENAI")
    APP_TIMEZONE: str = os.environ.get("APP_TIMEZONE", "Asia/Seoul")


settings = Settings()
