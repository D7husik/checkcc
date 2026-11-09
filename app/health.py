import logging

from fastapi import APIRouter, Response, status
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.db import engine
from app.schema_check import schema_state

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/health", tags=["health"])


@router.get("/live")
def live() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/ready")
def ready(response: Response) -> dict[str, object]:
    checks = {"mysql": "fail", "schema": "unknown"}
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
            checks["mysql"] = "ok"
            checks["schema"] = schema_state(connection)
    except SQLAlchemyError:
        logger.exception("Readiness check failed")

    if checks["mysql"] != "ok" or checks["schema"] in ("behind", "unknown"):
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {"status": "fail", "checks": checks}
    return {"status": "degraded" if checks["schema"] == "ahead" else "ok", "checks": checks}
