#!/usr/bin/env bash
# Send a deploy notification to Telegram.
#   scripts/notify_telegram.sh <test|prod> <icon> <message>
#
# TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID come from $APP_DIR/.deploy.env on the machine
# itself. Without them it only warns: a missing notification must not fail a deploy.

# shellcheck disable=SC1091
. "$(dirname "$0")/common.sh" "${1:-}"
ICON="${2:-ℹ️}"
MESSAGE="${3:-}"

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
  log "Telegram is not configured ($APP_DIR/.deploy.env), notification skipped: $MESSAGE"
  exit 0
fi

TEXT="$ICON checkcc · $ENV_NAME
$MESSAGE"
if [ -n "${GITHUB_RUN_ID:-}" ]; then
  TEXT="$TEXT
Автор: ${GITHUB_ACTOR:-?}
Run: ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
fi

if ! curl -fsS --max-time 10 -o /dev/null \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${TEXT}" \
    --data-urlencode "disable_web_page_preview=true"; then
  log "Telegram notification failed"
fi
exit 0
