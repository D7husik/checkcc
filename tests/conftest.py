import os

import pytest
from sqlalchemy.engine import make_url

TEST_URL = os.environ.get(
    "TEST_DATABASE_URL", "mysql+pymysql://checkcc:checkcc@127.0.0.1:3306/checkcc_test"
)
# The tests rewrite alembic_version: never let them near a real database.
if not (make_url(TEST_URL).database or "").endswith("_test"):
    pytest.exit(f"Refusing to run: database name must end in _test ({TEST_URL})", returncode=2)
os.environ["DATABASE_URL"] = TEST_URL

from alembic import command  # noqa: E402
from alembic.config import Config  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.db import engine  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture(scope="session", autouse=True)
def schema() -> None:
    command.upgrade(Config("alembic.ini"), "head")


@pytest.fixture
def client(schema):
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def db_connection():
    with engine.connect() as connection:
        yield connection
