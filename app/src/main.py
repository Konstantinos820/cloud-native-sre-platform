"""
FastAPI entrypoint.

Exposes:
  - GET  /health/startup  -> app has finished startup tasks (e.g. migrations)
  - GET  /health/live     -> process is alive (no DB check -> used for Liveness)
  - GET  /health/ready    -> app can serve traffic (DB check -> used for Readiness)
  - GET  /metrics         -> Prometheus exposition format
  - POST /users           -> create a user (increments business metric)
  - GET  /users           -> list users
  - GET  /users/{id}      -> fetch a single user
"""

import logging
import time
from contextlib import asynccontextmanager
from typing import Callable, Awaitable

from fastapi import FastAPI, Depends, HTTPException, Response, Request
from pydantic import BaseModel, EmailStr, ConfigDict
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError

from src.config import settings
from src.database import get_db, init_db, check_db_connection, User
from src.metrics import (
    HTTP_REQUESTS_TOTAL,
    HTTP_REQUEST_DURATION_SECONDS,
    USER_REGISTRATIONS_TOTAL,
)

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s"
)
logger = logging.getLogger(__name__)

# Tracks whether "startup work" (DB table creation / migrations) has completed.
# Used by /health/startup so the pod isn't marked ready before it, avoiding a
# race where traffic/probes hit the app before the schema exists.
app_state = {"startup_complete": False}


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Running startup tasks (schema init / migrations)...")
    try:
        init_db()
        app_state["startup_complete"] = True
        logger.info("Startup tasks complete.")
    except Exception:
        # Startup check will keep failing until the DB becomes reachable;
        # Kubernetes' startupProbe will keep retrying rather than crash-looping
        # the container immediately.
        logger.exception("Startup tasks failed - DB may not be reachable yet.")
        app_state["startup_complete"] = False
    yield
    logger.info("Shutting down.")


app = FastAPI(title=settings.APP_NAME, version=settings.APP_VERSION, lifespan=lifespan)


# --- Middleware: HTTP metrics -----------------------------------------------


@app.middleware("http")
async def prometheus_metrics_middleware(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    # /metrics itself is excluded so scraping doesn't inflate its own counters.
    if request.url.path == "/metrics":
        return await call_next(request)

    start_time = time.perf_counter()
    response: Response = await call_next(request)
    duration = time.perf_counter() - start_time

    # Use the matched route template (e.g. "/users/{user_id}") instead of the
    # raw path, to avoid unbounded label cardinality from path parameters.
    route = request.scope.get("route")
    path_label = route.path if route is not None else request.url.path

    HTTP_REQUESTS_TOTAL.labels(
        method=request.method,
        path=path_label,
        status_code=str(response.status_code),
    ).inc()

    HTTP_REQUEST_DURATION_SECONDS.labels(
        method=request.method,
        path=path_label,
    ).observe(duration)

    return response


# --- Schemas -----------------------------------------------------------------


class UserCreate(BaseModel):
    email: EmailStr
    full_name: str | None = None


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    email: EmailStr
    full_name: str | None = None


# --- Health endpoints ---------------------------------------------------------


@app.get("/health/startup", tags=["health"])
def health_startup():
    """
    Used by Kubernetes startupProbe.
    Returns 200 once schema init/migrations have completed; 503 until then.
    """
    if app_state["startup_complete"]:
        return {"status": "ok", "detail": "migrations applied"}
    raise HTTPException(status_code=503, detail="startup tasks not complete")


@app.get("/health/live", tags=["health"])
def health_live():
    """
    Used by Kubernetes livenessProbe.
    Intentionally does NOT touch the database: a slow/unavailable DB should
    not cause Kubernetes to restart an otherwise-healthy process.
    """
    return {"status": "alive"}


@app.get("/health/ready", tags=["health"])
def health_ready(response: Response):
    """
    Used by Kubernetes readinessProbe.
    Actively checks DB connectivity (SELECT 1). If the DB is unreachable,
    returns 503 so Kubernetes stops routing traffic to this pod - without
    killing/restarting it.
    """
    if check_db_connection():
        return {"status": "ready", "database": "reachable"}
    response.status_code = 503
    return {"status": "not_ready", "database": "unreachable"}


# --- Metrics endpoint ----------------------------------------------------------


@app.get("/metrics", tags=["observability"])
def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


# --- CRUD: users ----------------------------------------------------------------


@app.post("/users", response_model=UserOut, status_code=201, tags=["users"])
def create_user(payload: UserCreate, db: Session = Depends(get_db)):
    user = User(email=payload.email, full_name=payload.full_name)
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409, detail="A user with this email already exists"
        )
    db.refresh(user)

    # Business metric: increment only on a successful registration.
    USER_REGISTRATIONS_TOTAL.inc()

    return user


@app.get("/users", response_model=list[UserOut], tags=["users"])
def list_users(db: Session = Depends(get_db)):
    return db.query(User).order_by(User.id).all()


@app.get("/users/{user_id}", response_model=UserOut, tags=["users"])
def get_user(user_id: int, db: Session = Depends(get_db)):
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")
    return user


@app.get("/", tags=["meta"])
def root():
    return {"service": settings.APP_NAME, "version": settings.APP_VERSION}
