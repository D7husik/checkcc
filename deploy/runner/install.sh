#!/usr/bin/env bash
# Install a GitHub Actions runner as a systemd user service (no root needed).
#   deploy/runner/install.sh <name> <labels> <registration-token> [repo-url]
#
# The token comes from Settings → Actions → Runners → New self-hosted runner and lives
# one hour. To survive logout: sudo loginctl enable-linger "$USER".
# On a server with a dedicated user use GitHub's own `svc.sh install <user>` instead.

set -Eeuo pipefail

NAME="${1:?usage: install.sh <name> <labels> <token> [repo-url]}"
LABELS="${2:?labels are required}"
TOKEN="${3:?registration token is required}"
REPO_URL="${4:-https://github.com/D7husik/checkcc}"
VERSION="${RUNNER_VERSION:-2.338.2}"
DIR="$HOME/actions-runners/$NAME"

# config.sh records PATH in .path: the jobs need uv from here.
export PATH="$HOME/.local/bin:$PATH"

mkdir -p "$DIR"
cd "$DIR"
if [ ! -x ./config.sh ]; then
  curl -fsSL "https://github.com/actions/runner/releases/download/v$VERSION/actions-runner-linux-x64-$VERSION.tar.gz" \
    | tar xz
fi
./config.sh --unattended --replace --url "$REPO_URL" --token "$TOKEN" \
  --name "$(hostname)-$NAME" --labels "$LABELS" --work _work

UNIT="github-runner-$NAME.service"
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/$UNIT" <<UNIT_EOF
[Unit]
Description=GitHub Actions runner ($NAME)
After=network-online.target

[Service]
WorkingDirectory=$DIR
ExecStart=$DIR/run.sh
Restart=always
RestartSec=5
# Stop every process of the unit. With KillMode=process systemd kills only run.sh,
# the Listener outlives it, and after a restart two Listeners share one registration:
# "A session for this runner already exists", then jobs cancel each other.
# (svc.sh uses KillMode=process safely: its runsvc.sh forwards the signal.)
KillMode=control-group
TimeoutStopSec=5min

[Install]
WantedBy=default.target
UNIT_EOF

systemctl --user daemon-reload
systemctl --user enable --now "$UNIT"
echo "Runner $NAME is running: systemctl --user status $UNIT"
