#!/usr/bin/env bash
# One-off preparation of a machine without Docker: directories and the systemd unit.
#   scripts/host/setup.sh prod
#
# $APP_DIR/.lab_env and $APP_DIR/.my.cnf must be there already, see docs/CI_CD.md.

# shellcheck disable=SC1091
. "$(dirname "$0")/lib.sh" "${1:-}"

mkdir -p "$RELEASES_DIR" "$APP_DIR/logs" "$APP_DIR/backups"
for file in "$ENV_FILE" "$MY_CNF"; do
  [ -f "$file" ] || die "$file is missing: create it first, see docs/CI_CD.md"
  chmod 600 "$file"
done

render() {
  sed -e "s|@APP_DIR@|$APP_DIR|g" -e "s|@APP_HOST@|${APP_HOST:-127.0.0.1}|g" \
      -e "s|@APP_PORT@|$APP_PORT|g" -e "s|@WANTED_BY@|$1|g" \
      -e "$2" "$SOURCE_DIR/deploy/systemd/checkcc.service"
}

case "$SERVICE_MANAGER" in
  user)
    UNIT_DIR="$HOME/.config/systemd/user"
    mkdir -p "$UNIT_DIR"
    render default.target '/@USER_LINE@/d' > "$UNIT_DIR/$SERVICE_NAME"
    svc daemon-reload
    svc enable "$SERVICE_NAME"
    log "Installed $UNIT_DIR/$SERVICE_NAME. It starts with the first deploy."
    log "So that it runs without an open session: sudo loginctl enable-linger $USER"
    ;;
  system)
    OUT="$APP_DIR/$SERVICE_NAME"
    render multi-user.target "s|@USER_LINE@|User=$USER|" > "$OUT"
    log "Rendered $OUT. As root:"
    log "  cp $OUT /etc/systemd/system/$SERVICE_NAME && systemctl daemon-reload && systemctl enable $SERVICE_NAME"
    log "  visudo -f /etc/sudoers.d/checkcc   # see deploy/sudoers.example"
    ;;
  *) die "SERVICE_MANAGER must be user or system, got: $SERVICE_MANAGER" ;;
esac
