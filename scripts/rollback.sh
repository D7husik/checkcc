#!/usr/bin/env bash
# Bring back an earlier image on the test stand. The database is not touched.
#
#   scripts/rollback.sh test                 # to the image before the current one
#   scripts/rollback.sh test --to <image>    # to a given image (repo:tag)
#   ... --quiet                              # no Telegram message (deploy.sh sends its own)

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
[ -n "$TARGET" ] || die "no earlier image recorded in $STATE_FILE, pass --to <image>"

log "Rolling back app to $TARGET"
docker image inspect "$TARGET" >/dev/null 2>&1 || die "image $TARGET is not available"
APP_IMAGE="$TARGET" compose up -d --no-deps --no-build app

if ! wait_ready; then
  [ "$QUIET" = 1 ] || notify "❌" "Откат на ${TARGET##*:} не прошёл /health/ready. Нужен человек."
  die "$TARGET is not ready either"
fi

# A manual rollback swaps current and previous; after a failed deploy the target
# already is the current one and nothing changes.
if [ "$TARGET" != "$CURRENT" ]; then
  state_set "$TARGET" "$CURRENT"
fi
[ "$QUIET" = 1 ] || notify "↩️" "Ручной откат на ${TARGET##*:} выполнен."
log "Rolled back to $TARGET"
