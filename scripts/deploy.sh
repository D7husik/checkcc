#!/usr/bin/env bash
# Deploy one commit to the test stand (Docker Compose):
#   build image → backup → migrate (new image, one-off container) → switch app → wait /health/ready
# If the new app does not become ready, the image that served before is brought back.
#
#   scripts/deploy.sh test <sha>
#
# Runs on the stand itself (self-hosted runner or by hand). Secrets stay there:
# $APP_DIR/.lab_env for the app, $APP_DIR/.deploy.env for Telegram.

# shellcheck disable=SC1091
. "$(dirname "$0")/lib.sh" "${1:-}"
TAG="${2:-}"
[ -n "$TAG" ] || die "usage: deploy.sh test <sha>"
IMAGE="$IMAGE_REPO:${TAG:0:12}"
PREVIOUS="$(state_get current)"

fail() {
  trap - ERR
  notify "❌" "Деплой ${TAG:0:12} не выполнен: $1"
  die "$1"
}
# Anything not handled below still ends in a notification.
trap 'fail "непредвиденная ошибка в scripts/deploy.sh:$LINENO ($BASH_COMMAND)"' ERR

# --- 0. files the deployment runs from -----------------------------------
[ -f "$APP_DIR/.lab_env" ] || fail "нет $APP_DIR/.lab_env (настройки приложения), см. docs/CI_CD.md"
cp "$SOURCE_DIR/docker-compose.yml" "$APP_DIR/"
log "Deploying $IMAGE (project $COMPOSE_PROJECT_NAME, dir $APP_DIR, serving now: ${PREVIOUS:-nothing})"

# --- 1. image: built on the stand, nothing goes through a registry --------
docker build -t "$IMAGE" "$SOURCE_DIR" || fail "сборка образа упала"

# --- 2. database -----------------------------------------------------------
compose up -d --no-build --wait mysql || fail "MySQL не поднялась"

# --- 3. a database that Alembic does not manage is not ours to migrate ----
TABLES="$(mysql_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name <> 'alembic_version'")"
if [ "${TABLES:-0}" -gt 0 ] && [ -z "$(db_revision)" ]; then
  fail "в БД есть таблицы, но нет alembic_version: схема неизвестна, деплой остановлен"
fi

# --- 4. backup -------------------------------------------------------------
BACKUP="$("$SCRIPTS_DIR/backup_db.sh" "$ENV_NAME" "${TAG:0:12}")" || fail "бэкап не создан, ничего не менялось"

# --- 5. migrations, with the new image, before anything switches ---------
if ! APP_IMAGE="$IMAGE" compose run --rm --no-deps migrate; then
  fail "миграция упала. Приложение не переключалось. Схема могла измениться частично (DDL в MySQL не откатывается). Бэкап: $BACKUP"
fi

# --- 6. switch --------------------------------------------------------------
APP_IMAGE="$IMAGE" compose up -d --no-deps --no-build app || fail "контейнер app не запустился"

# --- 7. ready? --------------------------------------------------------------
if wait_ready; then
  state_set "$IMAGE" "$PREVIOUS"
  # Keep only the images we may roll back to.
  docker images "$IMAGE_REPO" --format '{{.Repository}}:{{.Tag}}' \
    | grep -vxF -e "$IMAGE" -e "${PREVIOUS:-none}" | xargs -r docker rmi >/dev/null 2>&1 || true
  notify "✅" "Задеплоен ${TAG:0:12}. Бэкап до миграции: $(basename "$BACKUP")"
  log "Deployed $IMAGE"
  exit 0
fi

# --- 8. automatic rollback -------------------------------------------------
log "$IMAGE is not ready, rolling back"
if [ -n "$PREVIOUS" ] && "$SCRIPTS_DIR/rollback.sh" "$ENV_NAME" --to "$PREVIOUS" --quiet; then
  notify "↩️" "Деплой ${TAG:0:12} не прошёл /health/ready: автооткат на ${PREVIOUS##*:}. Миграции остались применены. Бэкап: $(basename "$BACKUP")"
else
  notify "❌" "Деплой ${TAG:0:12} не прошёл /health/ready, откатиться не удалось (${PREVIOUS:-нет предыдущего образа}). Нужен человек. Бэкап: $(basename "$BACKUP")"
fi
exit 1
