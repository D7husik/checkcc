from sqlalchemy import text


def test_live(client):
    assert client.get("/health/live").json() == {"status": "ok"}


def test_ready(client):
    response = client.get("/health/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "checks": {"mysql": "ok", "schema": "ok"}}


def _set_revision(connection, revision):
    connection.execute(text("UPDATE alembic_version SET version_num = :rev"), {"rev": revision})
    connection.commit()


def _current_revision(connection):
    return connection.execute(text("SELECT version_num FROM alembic_version")).scalar()


def test_ready_degraded_when_schema_is_newer_than_code(client, db_connection):
    revision = _current_revision(db_connection)
    db_connection.commit()
    try:
        _set_revision(db_connection, "9999_from_the_future")
        response = client.get("/health/ready")
        assert response.status_code == 200
        assert response.json()["status"] == "degraded"
        assert response.json()["checks"]["schema"] == "ahead"
    finally:
        _set_revision(db_connection, revision)


def test_ready_fails_without_revision(client, db_connection):
    revision = _current_revision(db_connection)
    db_connection.execute(text("DELETE FROM alembic_version"))
    db_connection.commit()
    try:
        response = client.get("/health/ready")
        assert response.status_code == 503
        assert response.json()["checks"]["schema"] == "behind"
    finally:
        db_connection.execute(
            text("INSERT INTO alembic_version (version_num) VALUES (:rev)"), {"rev": revision}
        )
        db_connection.commit()
