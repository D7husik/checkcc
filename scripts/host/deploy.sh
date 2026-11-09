#!/usr/bin/env bash
# Deploy one commit to a machine without Docker:
#   new release dir + exact dependencies → backup → migrate (the old version keeps
#   serving) → switch `current` → restart the service → wait /health/ready
# If the new version does not become ready, the previous release is brought back.
#
#   scripts/host/deploy.sh prod <sha>
#
# Runs on the target machine (self-hosted runner or by hand), from a git checkout that
# has <sha>. Secrets stay there: $APP_DIR/.lab_env, .my.cnf, .deploy.env.

# shellcheck disable=SC1091
. "$(dirname "$0")/lib.sh" "${1:-}"
SHA="${2:-}"
[ -n "$SHA" ] || die "usage: scripts/host/deploy.sh prod <sha>"
SHORT="${SHA:0:12}"
PREVIOUS="$(state_get current)"
RELEASE="$(date -u +%Y%m%d-%H%M%S)_$SHORT"
RELEASE_PATH="$RELEASES_DIR/$RELEASE"

fail() {
  trap - ERR
  notify "❌" "Деплой $SHORT не выполнен: $1"
  die "$1"
}
# Anything not handled below still ends in a notification.
trap 'fail "непредвиденная ошибка в scripts/host/deploy.sh:$LINENO ($BASH_COMMAND)"' ERR

# --- 0. the machine is prepared (scripts/host/setup.sh) ---------------------
[ -f "$ENV_FILE" ] || fail "нет $ENV_FILE (настройки приложения), см. docs/CI_CD.md"
[ -f "$MY_CNF" ] || fail "нет $MY_CNF (доступ mysql/mysqldump), см. docs/CI_CD.md"
for tool in uv mysql mysqldump; do
  command -v "$tool" >/dev/null || fail "не установлен $tool"
done
svc cat "$SERVICE_NAME" >/dev/null 2>&1 || fail "сервис $SERVICE_NAME не установлен: выполните scripts/host/setup.sh $ENV_NAME"
log "Deploying $RELEASE (dir $APP_DIR, serving now: ${PREVIOUS:-nothing})"

# --- 1. the release: this commit's code and exactly the locked dependencies -
mkdir -p "$RELEASE_PATH" "$APP_DIR/logs"
git -C "$SOURCE_DIR" archive "$SHA" | tar -x -C "$RELEASE_PATH"
# The app writes to a relative logs/: every release shares one directory.
ln -s ../../logs "$RELEASE_PATH/logs"
(cd "$RELEASE_PATH" && UV_PROJECT_ENVIRONMENT=.venv uv sync --frozen --no-dev --no-install-project) \
  || fail "не удалось установить зависимости"

# --- 2. a database that Alembic does not manage is not ours to migrate ----
TABLES="$(mysql_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name <> 'alembic_version'")"
if [ "${TABLES:-0}" -gt 0 ] && [ -z "$(db_revision)" ]; then
  fail "в БД есть таблицы, но нет alembic_version: схема неизвестна, деплой остановлен"
fi

# --- 3. backup -------------------------------------------------------------
BACKUP="$("$SCRIPTS_DIR/host/backup_db.sh" "$ENV_NAME" "$SHORT")" || fail "бэкап не создан, ничего не менялось"

# --- 4. migrations, from the new release, before anything switches --------
if ! run_in_release "$RELEASE_PATH" .venv/bin/alembic upgrade head; then
  fail "миграция упала. Сервис не переключался и работает на ${PREVIOUS:-прежней версии}. Схема могла измениться частично (DDL в MySQL не откатывается). Бэкап: $BACKUP"
fi

# --- 5. switch: one process at a time, restart replaces it ----------------
switch_current "$RELEASE"
svc restart "$SERVICE_NAME" || fail "сервис $SERVICE_NAME не перезапустился"

# --- 6. ready? --------------------------------------------------------------
if wait_ready; then
  state_set "$RELEASE" "$PREVIOUS"
  prune_releases
  notify "✅" "Задеплоен $SHORT. Бэкап до миграции: $(basename "$BACKUP")"
  log "Deployed $RELEASE"
  exit 0
fi

# --- 7. automatic rollback -------------------------------------------------
log "$RELEASE is not ready, rolling back"
if [ -n "$PREVIOUS" ] && "$SCRIPTS_DIR/host/rollback.sh" "$ENV_NAME" --to "$PREVIOUS" --quiet; then
  notify "↩️" "Деплой $SHORT не прошёл /health/ready: автооткат на $PREVIOUS. Миграции остались применены. Бэкап: $(basename "$BACKUP")"
else
  svc stop "$SERVICE_NAME" || true
  notify "❌" "Деплой $SHORT не прошёл /health/ready, откатиться не удалось (${PREVIOUS:-нет предыдущего релиза}). Сервис остановлен, нужен человек. Бэкап: $(basename "$BACKUP")"
fi
exit 1
