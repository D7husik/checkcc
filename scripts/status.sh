#!/usr/bin/env bash
# What is deployed on this environment and is it healthy.
#   scripts/status.sh <test|prod>

# shellcheck disable=SC1091
. "$(dirname "$0")/common.sh" "${1:-}"

echo "$ENV_NAME ($APP_DIR)"
if [ -f "$STATE_FILE" ]; then cat "$STATE_FILE"; else echo "nothing deployed yet"; fi
echo "/health/ready: $(curl -sS --max-time 5 "http://127.0.0.1:${APP_PORT}/health/ready" 2>&1 || true)"
