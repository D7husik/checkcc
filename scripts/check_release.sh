#!/usr/bin/env bash
# Only what went through the test stand may reach prod. Without rulesets (private repo on
# the Free plan) this check is what enforces it:
#   - the commit on main is a merge, and its second parent is what test had;
#   - main's code is exactly that commit's code;
#   - deploy-test marked that commit as deployed.
# Needs GITHUB_SHA, GITHUB_REPOSITORY, GITHUB_API_URL, GH_TOKEN and full git history.

set -Eeuo pipefail

SHA="${GITHUB_SHA:?}"
stop() { echo "::error::$*"; exit 1; }

TESTED="$(git rev-parse -q --verify "$SHA^2" || true)"
[ -n "$TESTED" ] || stop "$SHA is not a merge: everything on main must come from test (PR test → main, merge commit)"

[ "$(git rev-parse "$SHA^{tree}")" = "$(git rev-parse "$TESTED^{tree}")" ] \
  || stop "main differs from the test commit $TESTED: merge main into test, let deploy-test pass, then PR test → main again"

STATE="$(curl -fsS -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
  "$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/commits/$TESTED/status" \
  | jq -r '[.statuses[] | select(.context == "deploy/test")][0].state // "none"')"
[ "$STATE" = success ] || stop "commit $TESTED has not been deployed to the test stand (deploy/test: $STATE)"

echo "Release ${SHA:0:12} = test commit ${TESTED:0:12}, deployed to the stand"
{
  echo "### Релиз ${SHA:0:12} готов к деплою на прод"
  echo "Запуск: **Actions → Deploy prod → Run workflow** (ветка \`main\`)."
  NEW="$(git diff --name-only --diff-filter=A "$SHA^1" "$SHA" -- alembic/versions)"
  if [ -n "$NEW" ]; then
    echo; echo "Новые миграции:"; echo '```'; echo "$NEW"; echo '```'
  else
    echo; echo "Новых миграций нет."
  fi
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
