#!/usr/bin/env bash
# Bring back an earlier release. The database is not touched: schema rollback is a human
# decision (alembic downgrade or scripts/host/restore_db.sh).
#
#   scripts/host/rollback.sh prod                  # to the release before the current one
#   scripts/host/rollback.sh prod --to <release>   # to a given directory name in releases/
#   ... --quiet                                    # no Telegram message (deploy.sh sends its own)

# shellcheck disable=SC1091
. "$(dirname "$0")/lib.sh" "${1:-}"
shift
TARGET=""
QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --to) TARGET="${2:-}"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done

CURRENT="$(state_get current)"
TARGET="${TARGET:-$(state_get previous)}"
[ -n "$TARGET" ] || die "no earlier release recorded in $STATE_FILE, pass --to <release>"
[ -d "$RELEASES_DIR/$TARGET" ] || die "release $TARGET is not in $RELEASES_DIR"

log "Rolling back to $TARGET"
switch_current "$TARGET"
svc restart "$SERVICE_NAME"

if ! wait_ready; then
  [ "$QUIET" = 1 ] || notify "❌" "Откат на $TARGET не прошёл /health/ready. Нужен человек."
  die "$TARGET is not ready either"
fi

# A manual rollback swaps current and previous; after a failed deploy the target
# already is the current one and nothing changes.
if [ "$TARGET" != "$CURRENT" ]; then
  state_set "$TARGET" "$CURRENT"
fi
[ "$QUIET" = 1 ] || notify "↩️" "Ручной откат на $TARGET выполнен."
log "Rolled back to $TARGET"
