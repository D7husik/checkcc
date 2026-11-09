#!/usr/bin/env bash
# Helpers for the Docker Compose deployment (the test stand). Sourced:
#   . "$(dirname "$0")/lib.sh" <test>

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/common.sh" "${1:-}"

: "${COMPOSE_PROJECT_NAME:?COMPOSE_PROJECT_NAME is not set: this environment is not a compose one}"
IMAGE_REPO="${IMAGE_REPO:-checkcc}"
export APP_DIR COMPOSE_PROJECT_NAME APP_PORT MYSQL_HOST_PORT

compose() {
  docker compose --project-directory "$APP_DIR" -p "$COMPOSE_PROJECT_NAME" \
    -f "$APP_DIR/docker-compose.yml" "$@"
}

# Run SQL against the environment's database inside the mysql container.
mysql_query() {
  # shellcheck disable=SC2016  # expanded inside the mysql container
  printf '%s\n' "$1" | compose exec -T mysql sh -c \
    'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -B "$MYSQL_DATABASE"' \
    2> >(grep -v 'Using a password' >&2 || true)
}

# The database's alembic revision, empty when there is no alembic_version.
db_revision() {
  local has
  has="$(mysql_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'alembic_version'")"
  [ "${has:-0}" -gt 0 ] || return 0
  mysql_query "SELECT version_num FROM alembic_version" | tr '\n' ' ' | sed 's/ *$//'
}
