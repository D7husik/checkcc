import logging
from pathlib import Path

from alembic.config import Config
from alembic.script import ScriptDirectory
from sqlalchemy import inspect, text
from sqlalchemy.engine import Connection

from app.db import engine

logger = logging.getLogger(__name__)

ROOT = Path(__file__).resolve().parent.parent


def _scripts() -> ScriptDirectory:
    config = Config()
    config.set_main_option("script_location", str(ROOT / "alembic"))
    return ScriptDirectory.from_config(config)


def schema_state(connection: Connection) -> str:
    """ok, behind (older than this code, or not managed by Alembic) or ahead.

    A revision this code does not know is newer than the code: that is what a rollback
    of the app leaves behind, so it must not stop the old version from starting.
    """
    if not inspect(connection).has_table("alembic_version"):
        return "behind"
    revision = connection.execute(text("SELECT version_num FROM alembic_version")).scalar()
    if revision is None:
        return "behind"
    scripts = _scripts()
    if revision == scripts.get_current_head():
        return "ok"
    known = {script.revision for script in scripts.walk_revisions()}
    return "behind" if revision in known else "ahead"


def ensure_schema() -> None:
    with engine.connect() as connection:
        state = schema_state(connection)
    if state == "behind":
        raise RuntimeError("Database schema is behind this code: run `alembic upgrade head`")
    if state == "ahead":
        logger.warning("Database schema is newer than this code (rolled back release?)")
