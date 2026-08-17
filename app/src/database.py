"""
Database layer: SQLAlchemy engine/session management, ORM models,
and a lightweight health-check helper used by the /health/ready probe.
"""

import logging
from contextlib import contextmanager
from datetime import datetime, timezone

from opentelemetry.instrumentation.sqlalchemy import (
    SQLAlchemyInstrumentor,  # type: ignore
)
from sqlalchemy import Column, DateTime, Integer, String, create_engine, text
from sqlalchemy.exc import OperationalError, SQLAlchemyError
from sqlalchemy.orm import Session, declarative_base, sessionmaker

from src.config import settings

logger = logging.getLogger(__name__)

# pool_pre_ping=True avoids handing out dead connections from the pool
# (e.g. after the DB briefly restarts) - cheap insurance for a small app.
engine = create_engine(
    settings.DATABASE_URL,
    pool_pre_ping=True,
    pool_size=settings.DB_POOL_SIZE,
    max_overflow=settings.DB_MAX_OVERFLOW,
    pool_timeout=settings.DB_POOL_TIMEOUT,
    future=True,
)

# Instrument SQLAlchemy engine for OpenTelemetry traces
if settings.OTEL_TRACES_ENABLED:
    SQLAlchemyInstrumentor().instrument(engine=engine)

SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, future=True)

Base = declarative_base()


class User(Base):
    """Minimal user model - enough to demonstrate real CRUD + a business metric."""

    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(255), unique=True, nullable=False, index=True)
    full_name = Column(String(255), nullable=True)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )


def init_db() -> None:
    """
    Create tables if they don't exist yet.

    NOTE: this stands in for a real migration tool (e.g. Alembic) for the
    scope of Week 1. It's called once during the app startup/"migrations"
    step referenced by the /health/startup probe.
    """
    Base.metadata.create_all(bind=engine)


def get_db():
    """FastAPI dependency that yields a request-scoped DB session."""
    db: Session = SessionLocal()
    try:
        yield db
    finally:
        db.close()


@contextmanager
def db_session_scope():
    """Context-manager version, used outside of request handlers (e.g. health checks)."""
    db: Session = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def check_db_connection() -> bool:
    """
    Lightweight liveness/readiness helper: runs `SELECT 1` against the DB.
    Returns True if the database answered, False otherwise.
    Never raises - callers just get a boolean.
    """
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return True
    except (OperationalError, SQLAlchemyError) as exc:
        logger.warning("Database readiness check failed: %s", exc)
        return False
