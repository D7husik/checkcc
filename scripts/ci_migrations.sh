#!/usr/bin/env bash
# Migration checks for CI: one head, upgrade on an empty database, models match the
# migrations, and the whole history can go down and up again.
#   DATABASE_URL=.../checkcc_empty scripts/ci_migrations.sh

set -Eeuo pipefail

case "${DATABASE_URL:?DATABASE_URL is required}" in
  *_empty) ;;
  *) echo "Refusing to run: the database name must end in _empty" >&2; exit 2 ;;
esac

HEADS="$(alembic heads | grep -c '(head)')"
if [ "$HEADS" -ne 1 ]; then
  echo "::error::Expected one Alembic head, found $HEADS. Merge them or fix down_revision"
  exit 1
fi

alembic upgrade head
alembic check
alembic downgrade base
alembic upgrade head
alembic check
