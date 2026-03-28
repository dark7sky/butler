import os
from pydantic_settings import BaseSettings


def _env_bool(name: str, default: bool) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


class Settings(BaseSettings):
    PROJECT_NAME: str = "TA WatchDog API"
    VERSION: str = "1.0.0"

    SECRET_KEY: str = os.environ.get(
        "SECRET_KEY", "your-super-secret-key-change-it-in-production"
    )
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7

    MASTER_PASSWORD: str = os.environ.get("MASTER_PASSWORD", "admin")
    LOGIN_RATE_LIMIT_ENABLED: bool = _env_bool("LOGIN_RATE_LIMIT_ENABLED", True)
    LOGIN_RATE_LIMIT_MAX_ATTEMPTS: int = int(
        os.environ.get("LOGIN_RATE_LIMIT_MAX_ATTEMPTS", "5")
    )
    LOGIN_RATE_LIMIT_WINDOW_SECONDS: int = int(
        os.environ.get("LOGIN_RATE_LIMIT_WINDOW_SECONDS", "600")
    )
    LOGIN_RATE_LIMIT_BLOCK_SECONDS: int = int(
        os.environ.get("LOGIN_RATE_LIMIT_BLOCK_SECONDS", "900")
    )

    DATABASE_URL: str = os.environ.get(
        "DATABASE_URL", "postgresql://postgres:password@localhost:5432/postgres"
    )
    KEY_OPENAI: str | None = os.environ.get("KEY_OPENAI")
    APP_TIMEZONE: str = os.environ.get("APP_TIMEZONE", "Asia/Seoul")


settings = Settings()
