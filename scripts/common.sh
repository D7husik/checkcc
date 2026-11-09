#!/usr/bin/env bash
# Shared by the compose scripts (scripts/lib.sh) and the systemd ones (scripts/host/lib.sh).
# Sourced, never run directly. Reads deploy/<env>.env (settings, in git), then
# $APP_DIR/.deploy.env (secrets and per-machine overrides, only on the machine).

set -Eeuo pipefail

ENV_NAME="${1:-}"
case "$ENV_NAME" in
  test|prod) ;;
  *) echo "environment must be test or prod, got: '${ENV_NAME}'" >&2; exit 2 ;;
esac

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(dirname "$SCRIPTS_DIR")"   # a repo checkout, or the copy in $APP_DIR

set -a
# shellcheck disable=SC1090
. "$SOURCE_DIR/deploy/$ENV_NAME.env"
if [ -f "$APP_DIR/.deploy.env" ]; then
  # shellcheck disable=SC1091
  . "$APP_DIR/.deploy.env"
fi
set +a

HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-90}"
BACKUP_KEEP="${BACKUP_KEEP:-14}"
STATE_FILE="$APP_DIR/.deployed"

log() { printf '[%s %s] %s\n' "$(date -u +%H:%M:%S)" "$ENV_NAME" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

# .deployed holds what is serving now and what served before it.
state_get() {
  [ -f "$STATE_FILE" ] || return 0
  sed -n "s/^$1=//p" "$STATE_FILE" | tail -n 1
}

state_set() {
  printf 'current=%s\nprevious=%s\nupdated_at=%s\n' "$1" "$2" "$(date -u +%FT%TZ)" > "$STATE_FILE.tmp"
  mv "$STATE_FILE.tmp" "$STATE_FILE"
}

# Wait until /health/ready answers 200 (ok or degraded); 503 means not yet.
wait_ready() {
  local url="http://127.0.0.1:${APP_PORT}/health/ready" deadline=$((SECONDS + HEALTH_TIMEOUT)) body
  while [ "$SECONDS" -lt "$deadline" ]; do
    if body="$(curl -fsS --max-time 5 "$url" 2>/dev/null)"; then
      log "ready: $body"
      return 0
    fi
    sleep 3
  done
  log "not ready after ${HEALTH_TIMEOUT}s: $(curl -sS --max-time 5 "$url" 2>&1 || true)"
  return 1
}

notify() {
  "$SCRIPTS_DIR/notify_telegram.sh" "$ENV_NAME" "$@" || true
}
