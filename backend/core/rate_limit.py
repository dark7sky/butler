from collections import deque
from dataclasses import dataclass
from math import ceil
from threading import Lock
import time

from core.config import settings


@dataclass(frozen=True)
class RateLimitDecision:
    allowed: bool
    retry_after_seconds: int = 0


class LoginRateLimiter:
    def __init__(
        self,
        *,
        enabled: bool,
        max_attempts: int,
        window_seconds: int,
        block_seconds: int,
    ) -> None:
        self.enabled = enabled
        self.max_attempts = max(1, max_attempts)
        self.window_seconds = max(1, window_seconds)
        self.block_seconds = max(1, block_seconds)
        self._failed_attempts: dict[str, deque[float]] = {}
        self._blocked_until: dict[str, float] = {}
        self._last_cleanup = 0.0
        self._lock = Lock()

    def check(self, key: str) -> RateLimitDecision:
        if not self.enabled:
            return RateLimitDecision(allowed=True)

        now = time.time()
        with self._lock:
            self._cleanup(now)
            retry_after = self._retry_after_seconds(key, now)
            if retry_after > 0:
                return RateLimitDecision(
                    allowed=False, retry_after_seconds=retry_after
                )
            return RateLimitDecision(allowed=True)

    def record_failure(self, key: str) -> RateLimitDecision:
        if not self.enabled:
            return RateLimitDecision(allowed=True)

        now = time.time()
        with self._lock:
            self._cleanup(now)

            retry_after = self._retry_after_seconds(key, now)
            if retry_after > 0:
                return RateLimitDecision(
                    allowed=False, retry_after_seconds=retry_after
                )

            attempts = self._failed_attempts.setdefault(key, deque())
            attempts.append(now)
            self._prune_attempts(key, now)

            if len(attempts) >= self.max_attempts:
                blocked_until = now + self.block_seconds
                self._blocked_until[key] = blocked_until
                self._failed_attempts.pop(key, None)
                return RateLimitDecision(
                    allowed=False,
                    retry_after_seconds=max(1, ceil(blocked_until - now)),
                )

            return RateLimitDecision(allowed=True)

    def record_success(self, key: str) -> None:
        if not self.enabled:
            return

        with self._lock:
            self._failed_attempts.pop(key, None)
            self._blocked_until.pop(key, None)

    def _retry_after_seconds(self, key: str, now: float) -> int:
        blocked_until = self._blocked_until.get(key)
        if blocked_until is None:
            return 0
        if blocked_until <= now:
            self._blocked_until.pop(key, None)
            return 0
        return max(1, ceil(blocked_until - now))

    def _prune_attempts(self, key: str, now: float) -> None:
        attempts = self._failed_attempts.get(key)
        if attempts is None:
            return

        cutoff = now - self.window_seconds
        while attempts and attempts[0] <= cutoff:
            attempts.popleft()

        if not attempts:
            self._failed_attempts.pop(key, None)

    def _cleanup(self, now: float) -> None:
        if now - self._last_cleanup < 60:
            return

        self._last_cleanup = now
        for key in list(self._failed_attempts.keys()):
            self._prune_attempts(key, now)

        for key, blocked_until in list(self._blocked_until.items()):
            if blocked_until <= now:
                self._blocked_until.pop(key, None)


login_rate_limiter = LoginRateLimiter(
    enabled=settings.LOGIN_RATE_LIMIT_ENABLED,
    max_attempts=settings.LOGIN_RATE_LIMIT_MAX_ATTEMPTS,
    window_seconds=settings.LOGIN_RATE_LIMIT_WINDOW_SECONDS,
    block_seconds=settings.LOGIN_RATE_LIMIT_BLOCK_SECONDS,
)
