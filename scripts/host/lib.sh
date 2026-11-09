#!/usr/bin/env bash
# Helpers for the deployment without Docker: a systemd service, a directory per release
# and a `current` link. Sourced:
#   . "$(dirname "$0")/lib.sh" <prod>

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../common.sh" "${1:-}"

: "${SERVICE_NAME:?SERVICE_NAME is not set: this environment is not a systemd one}"
: "${SERVICE_MANAGER:?SERVICE_MANAGER must be user or system}"
: "${DB_NAME:?DB_NAME is not set}"
KEEP_RELEASES="${KEEP_RELEASES:-5}"
RELEASES_DIR="$APP_DIR/releases"
CURRENT_LINK="$APP_DIR/current"
ENV_FILE="$APP_DIR/.lab_env"
MY_CNF="$APP_DIR/.my.cnf"

# user: `systemctl --user`, no privileges at all. system: only start/stop/restart go
# through sudo, and sudoers allows exactly those (deploy/sudoers.example).
svc() {
  case "$SERVICE_MANAGER" in
    user)
      XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" systemctl --user "$@" ;;
    system)
      case "$1" in
        start|stop|restart) sudo -n systemctl "$@" ;;
        *) systemctl "$@" ;;
      esac ;;
    *) die "SERVICE_MANAGER must be user or system, got: $SERVICE_MANAGER" ;;
  esac
}

mysql_query() {
  printf '%s\n' "$1" | mysql --defaults-extra-file="$MY_CNF" -N -B "$DB_NAME"
}

db_revision() {
  local has
  has="$(mysql_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'alembic_version'")"
  [ "${has:-0}" -gt 0 ] || return 0
  mysql_query "SELECT version_num FROM alembic_version" | tr '\n' ' ' | sed 's/ *$//'
}

# Run a command from a release directory, with the settings of this machine.
run_in_release() {
  local release_path="$1"
  shift
  (cd "$release_path" && LAB_ENV_PATH="$ENV_FILE" "$@")
}

# Atomic: the link always points at a complete release.
switch_current() {
  ln -sfn "releases/$1" "$CURRENT_LINK.tmp"
  mv -Tf "$CURRENT_LINK.tmp" "$CURRENT_LINK"
}

# Keep the newest KEEP_RELEASES, and always the two a rollback may need.
prune_releases() {
  local current previous name
  current="$(state_get current)"
  previous="$(state_get previous)"
  # shellcheck disable=SC2012  # our own directory names, no spaces
  ls -1t "$RELEASES_DIR" | tail -n +"$((KEEP_RELEASES + 1))" | while read -r name; do
    if [ "$name" != "$current" ] && [ "$name" != "$previous" ]; then
      rm -rf "${RELEASES_DIR:?}/$name"
    fi
  done
}
