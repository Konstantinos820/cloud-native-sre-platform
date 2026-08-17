"""
Application configuration loaded from environment variables.
Kept intentionally simple (no external secrets manager) for the
local-first / Kind cluster phase of the project.
"""

import os


class Settings:
    # Individual pieces (useful for Kubernetes Secrets / Sealed Secrets,
    # where each field is usually injected as its own env var).
    POSTGRES_USER: str = os.getenv("POSTGRES_USER", "app_user")
    POSTGRES_PASSWORD: str = os.getenv("POSTGRES_PASSWORD", "app_password")
    POSTGRES_HOST: str = os.getenv("POSTGRES_HOST", "localhost")
    POSTGRES_PORT: str = os.getenv("POSTGRES_PORT", "5432")
    POSTGRES_DB: str = os.getenv("POSTGRES_DB", "app_db")

    # Allow a full DSN override (handy for local dev / docker-compose),
    # otherwise build it from the individual pieces above (handy for k8s).
    DATABASE_URL: str = os.getenv(
        "DATABASE_URL",
        f"postgresql+psycopg2://{POSTGRES_USER}:{POSTGRES_PASSWORD}"
        f"@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}",
    )

    APP_NAME: str = os.getenv("APP_NAME", "sre-platform-api")
    APP_VERSION: str = os.getenv("APP_VERSION", "0.1.0")

    # Pool sizing kept small on purpose - this is a local/demo workload.
    DB_POOL_SIZE: int = int(os.getenv("DB_POOL_SIZE", "5"))
    DB_MAX_OVERFLOW: int = int(os.getenv("DB_MAX_OVERFLOW", "5"))
    DB_POOL_TIMEOUT: int = int(os.getenv("DB_POOL_TIMEOUT", "5"))

    # OpenTelemetry Tracing Configurations
    OTEL_TRACES_ENABLED: bool = (
        os.getenv("OTEL_TRACES_ENABLED", "true").lower() == "true"
    )
    OTEL_SERVICE_NAME: str = os.getenv("OTEL_SERVICE_NAME", "sre-platform-api")
    OTEL_EXPORTER_OTLP_ENDPOINT: str = os.getenv(
        "OTEL_EXPORTER_OTLP_ENDPOINT", "http://tempo.monitoring.svc.cluster.local:4317"
    )


settings = Settings()
