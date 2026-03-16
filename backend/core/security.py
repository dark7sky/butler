from datetime import datetime, timedelta
import jwt
from core.config import settings

def create_access_token(data: dict, expires_delta: timedelta | None = None) -> str:
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=15)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
    return encoded_jwt

def verify_password(plain_password: str) -> bool:
    # In a real application, you should hash logic here.
    # For a personal app with a single secure master password, a direct comparison might suffice.
    return plain_password == settings.MASTER_PASSWORD
