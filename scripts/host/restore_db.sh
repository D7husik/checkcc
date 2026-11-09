#!/usr/bin/env bash
# Restore the database from a dump made by backup_db.sh.
# Destructive: everything written after the dump is lost. By hand only.
#
#   scripts/host/restore_db.sh prod <backup.sql.gz>
#
# The service is stopped while the dump loads. Afterwards start the release whose schema
# matches the dump: scripts/host/rollback.sh prod --to <release>.

# shellcheck disable=SC1091
. "$(dirname "$0")/lib.sh" "${1:-}"
FILE="${2:-}"
[ -f "$FILE" ] || die "usage: scripts/host/restore_db.sh prod <backup.sql.gz>"
gzip -dc "$FILE" | tail -n 1 | grep -q 'Dump completed' || die "$FILE is not a complete dump"

echo "Restore $ENV_NAME database from $(basename "$FILE")?"
echo "Everything written after this dump will be lost. Type the environment name to continue:"
read -r ANSWER
[ "$ANSWER" = "$ENV_NAME" ] || die "aborted"

log "Safety backup of the current state first"
"$SCRIPTS_DIR/host/backup_db.sh" "$ENV_NAME" "pre-restore" >/dev/null

svc stop "$SERVICE_NAME"
log "Loading $FILE"
gzip -dc "$FILE" | mysql --defaults-extra-file="$MY_CNF" "$DB_NAME"

log "Restored. The service is stopped: start the release that matches this schema, e.g."
log "  scripts/host/rollback.sh $ENV_NAME --to <release>"
