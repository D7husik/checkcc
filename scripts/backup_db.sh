#!/usr/bin/env bash
# Dump the test stand's database to $APP_DIR/backups/<env>/ and keep the last
# BACKUP_KEEP dumps. Prints the file path on stdout.
#   scripts/backup_db.sh test [label]

# shellcheck disable=SC1091
. "$(dirname "$0")/lib.sh" "${1:-}"
LABEL="${2:-manual}"
LABEL="${LABEL:0:12}"

DIR="$APP_DIR/backups/$ENV_NAME"
mkdir -p "$DIR"
chmod 700 "$APP_DIR/backups" "$DIR"
FILE="$DIR/db_$(date -u +%Y%m%d-%H%M%S)_${LABEL}.sql.gz"

log "Backing up to $FILE"
# shellcheck disable=SC2016  # expanded inside the mysql container
compose exec -T mysql sh -c \
  'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --quick --routines --triggers --no-tablespaces --set-gtid-purged=OFF "$MYSQL_DATABASE"' \
  2> >(grep -v 'Using a password' >&2 || true) \
  | gzip > "$FILE.part"

# mysqldump writes this line last; without it the dump was cut short.
if ! gzip -dc "$FILE.part" | tail -n 1 | grep -q 'Dump completed'; then
  rm -f "$FILE.part"
  die "backup is incomplete, nothing was changed"
fi
mv "$FILE.part" "$FILE"
chmod 600 "$FILE"
log "Backup done: $(du -h "$FILE" | cut -f1)"

# Keep the newest BACKUP_KEEP dumps (our own file names, no spaces).
# shellcheck disable=SC2012
ls -1t "$DIR"/db_*.sql.gz | tail -n +"$((BACKUP_KEEP + 1))" | xargs -r rm --

echo "$FILE"
