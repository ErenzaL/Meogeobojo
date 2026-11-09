import os


def allowed_origins() -> list[str]:
    """CORS allow-list from ALLOWED_ORIGINS (comma separated). Empty = none."""
    return [o.strip() for o in os.getenv("ALLOWED_ORIGINS", "").split(",") if o.strip()]


def mock_enabled() -> bool:
    """The mock only runs when explicitly enabled, so a deployment can never
    silently serve fake recommendations."""
    return os.getenv("ENABLE_MOCK_MODEL", "").lower() in {"1", "true", "yes"}
