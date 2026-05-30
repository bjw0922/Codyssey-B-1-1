#!/usr/bin/env bash
set -u

if [ "$(id -u)" -eq 0 ]; then
  echo "[ERROR] Do not run the agent application as root."
  exit 1
fi

if [ -f /etc/agent-app.env ]; then
  # shellcheck disable=SC1091
  . /etc/agent-app.env
fi

AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_UPLOAD_DIR="${AGENT_UPLOAD_DIR:-$AGENT_HOME/upload_files}"
AGENT_KEY_PATH="${AGENT_KEY_PATH:-$AGENT_HOME/api_keys/t_secret.key}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"

export AGENT_HOME AGENT_PORT AGENT_UPLOAD_DIR AGENT_KEY_PATH AGENT_LOG_DIR

APP_BIN="$AGENT_HOME/agent-app"
if [ ! -x "$APP_BIN" ]; then
  echo "[ERROR] Application binary is not executable: $APP_BIN"
  exit 1
fi

exec "$APP_BIN"
