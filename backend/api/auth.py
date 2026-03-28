from datetime import timedelta
from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordRequestForm

from core.config import settings
from core.security import verify_password, create_access_token
from core.rate_limit import login_rate_limiter
from schemas.token import Token

router = APIRouter()


def _client_key(request: Request) -> str:
    client = request.client
    return client.host if client and client.host else "unknown"


def _rate_limit_error(retry_after_seconds: int) -> HTTPException:
    minutes = max(1, retry_after_seconds // 60)
    return HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail=(
            "Too many failed login attempts. "
            f"Try again in about {minutes} minute(s)."
        ),
        headers={"Retry-After": str(retry_after_seconds)},
    )


@router.post("/login", response_model=Token)
async def login_for_access_token(
    request: Request, form_data: OAuth2PasswordRequestForm = Depends()
):
    client_key = _client_key(request)
    decision = login_rate_limiter.check(client_key)
    if not decision.allowed:
        raise _rate_limit_error(decision.retry_after_seconds)

    if not verify_password(form_data.password):
        failure_decision = login_rate_limiter.record_failure(client_key)
        if not failure_decision.allowed:
            raise _rate_limit_error(failure_decision.retry_after_seconds)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    login_rate_limiter.record_success(client_key)
    access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": form_data.username}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}
