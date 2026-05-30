#!/usr/bin/env bash
set -euo pipefail

AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_UPLOAD_DIR="$AGENT_HOME/upload_files"
AGENT_KEY_PATH="$AGENT_HOME/api_keys/t_secret.key"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
ARCHIVE_DIR="${ARCHIVE_DIR:-/var/log/monitor/agent-app/archive}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] Run this script with sudo or root."
  exit 1
fi

require_or_warn() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[WARNING] command not found: $1"
  fi
}

create_group() {
  local group_name="$1"
  if getent group "$group_name" >/dev/null; then
    echo "[OK] group exists: $group_name"
  else
    groupadd "$group_name"
    echo "[OK] group created: $group_name"
  fi
}

create_user() {
  local user_name="$1"
  if id "$user_name" >/dev/null 2>&1; then
    echo "[OK] user exists: $user_name"
  else
    useradd -m -s /bin/bash "$user_name"
    echo "[OK] user created: $user_name"
  fi
}

select_app_binary() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64)
      echo "$PROJECT_DIR/app/agent-app-linux-x86"
      ;;
    aarch64|arm64)
      echo "$PROJECT_DIR/app/agent-app-linux-arm64"
      ;;
    *)
      echo ""
      ;;
  esac
}

echo "====== AGENT SERVER SETUP ======"

echo

echo "[1] Packages check"
require_or_warn sudo
require_or_warn sshd
require_or_warn ufw
require_or_warn cron
require_or_warn ss
require_or_warn getfacl

echo

echo "[2] Users and groups"
create_group agent-common
create_group agent-core
create_user agent-admin
create_user agent-dev
create_user agent-test
usermod -aG agent-common,agent-core agent-admin
usermod -aG agent-common,agent-core agent-dev
usermod -aG agent-common agent-test
echo "[OK] group membership updated"

echo

echo "[3] Directories and application files"
mkdir -p "$AGENT_HOME/bin" "$AGENT_UPLOAD_DIR" "$(dirname "$AGENT_KEY_PATH")" "$AGENT_LOG_DIR" "$ARCHIVE_DIR"

APP_SRC="$(select_app_binary)"
if [ -z "$APP_SRC" ] || [ ! -f "$APP_SRC" ]; then
  echo "[ERROR] Cannot find app binary for this architecture. Check ./app directory."
  exit 1
fi
cp -f "$APP_SRC" "$AGENT_HOME/agent-app"
cp -f "$SCRIPT_DIR/monitor.sh" "$AGENT_HOME/bin/monitor.sh"
cp -f "$SCRIPT_DIR/report.sh" "$AGENT_HOME/bin/report.sh"
cp -f "$SCRIPT_DIR/log_retention.sh" "$AGENT_HOME/bin/log_retention.sh"
cp -f "$SCRIPT_DIR/run_agent.sh" "$AGENT_HOME/bin/run_agent.sh"
printf 'agent_api_key_test\n' > "$AGENT_KEY_PATH"

cat > /etc/agent-app.env <<ENVEOF
export AGENT_HOME=$AGENT_HOME
export AGENT_PORT=$AGENT_PORT
export AGENT_UPLOAD_DIR=$AGENT_UPLOAD_DIR
export AGENT_KEY_PATH=$AGENT_KEY_PATH
export AGENT_LOG_DIR=$AGENT_LOG_DIR
export LOG_FILE=$AGENT_LOG_DIR/monitor.log
export APP_PATTERN=agent_app.py|agent-app-linux-x86|agent-app-linux-arm64|$AGENT_HOME/agent-app
ENVEOF

chown -R agent-admin:agent-core "$AGENT_HOME"
chown agent-admin:agent-common "$AGENT_UPLOAD_DIR"
chown -R agent-admin:agent-core "$(dirname "$AGENT_KEY_PATH")" "$AGENT_LOG_DIR" "$ARCHIVE_DIR"
chown agent-dev:agent-core "$AGENT_HOME/bin/monitor.sh" "$AGENT_HOME/bin/report.sh" "$AGENT_HOME/bin/log_retention.sh" "$AGENT_HOME/bin/run_agent.sh"
chown agent-admin:agent-core "$AGENT_HOME/agent-app"

chmod 750 "$AGENT_HOME"
chmod 2750 "$AGENT_HOME/bin"
chmod 2770 "$AGENT_UPLOAD_DIR"
chmod 2770 "$(dirname "$AGENT_KEY_PATH")" "$AGENT_LOG_DIR" "$ARCHIVE_DIR"
chmod 660 "$AGENT_KEY_PATH"
chmod 750 "$AGENT_HOME/bin/monitor.sh" "$AGENT_HOME/bin/report.sh" "$AGENT_HOME/bin/log_retention.sh" "$AGENT_HOME/bin/run_agent.sh"
chmod 750 "$AGENT_HOME/agent-app"

if command -v setfacl >/dev/null 2>&1; then
  setfacl -m g:agent-common:rwx "$AGENT_UPLOAD_DIR"
  setfacl -d -m g:agent-common:rwx "$AGENT_UPLOAD_DIR"
  setfacl -m g:agent-core:rwx "$(dirname "$AGENT_KEY_PATH")" "$AGENT_LOG_DIR" "$ARCHIVE_DIR"
  setfacl -d -m g:agent-core:rwx "$(dirname "$AGENT_KEY_PATH")" "$AGENT_LOG_DIR" "$ARCHIVE_DIR"
fi
echo "[OK] files and permissions configured"

echo

echo "[4] SSH configuration"
if [ -f /etc/ssh/sshd_config ]; then
  cp -n /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true
  if grep -Eq '^#?Port ' /etc/ssh/sshd_config; then
    sed -i 's/^#\?Port .*/Port 20022/' /etc/ssh/sshd_config
  else
    printf '\nPort 20022\n' >> /etc/ssh/sshd_config
  fi
  if grep -Eq '^#?PermitRootLogin ' /etc/ssh/sshd_config; then
    sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
  else
    printf '\nPermitRootLogin no\n' >> /etc/ssh/sshd_config
  fi
  mkdir -p /run/sshd
  if command -v service >/dev/null 2>&1; then
    service ssh restart 2>/dev/null || service sshd restart 2>/dev/null || echo "[WARNING] ssh service restart failed. Check manually."
  elif command -v systemctl >/dev/null 2>&1; then
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || echo "[WARNING] ssh systemctl restart failed. Check manually."
  fi
  echo "[OK] sshd_config updated"
else
  echo "[WARNING] /etc/ssh/sshd_config not found. Install openssh-server in Ubuntu."
fi

echo

echo "[5] Firewall configuration"
if command -v ufw >/dev/null 2>&1; then
  ufw --force reset >/dev/null 2>&1 || true
  ufw default deny incoming >/dev/null 2>&1 || true
  ufw default allow outgoing >/dev/null 2>&1 || true
  ufw allow 20022/tcp >/dev/null 2>&1 || true
  ufw allow 15034/tcp >/dev/null 2>&1 || true
  ufw --force enable >/dev/null 2>&1 || echo "[WARNING] ufw enable failed. Docker/OrbStack may need privileged mode."
  ufw status numbered || true
else
  echo "[WARNING] ufw not installed. Run: apt update && apt install -y ufw"
fi

echo

echo "[6] Cron registration"
CRON_LINE="* * * * * $AGENT_HOME/bin/monitor.sh >/dev/null 2>&1"
CURRENT_CRON="$(mktemp)"
crontab -u agent-admin -l > "$CURRENT_CRON" 2>/dev/null || true
if ! grep -Fxq "$CRON_LINE" "$CURRENT_CRON"; then
  printf '%s\n' "$CRON_LINE" >> "$CURRENT_CRON"
  crontab -u agent-admin "$CURRENT_CRON"
fi
rm -f "$CURRENT_CRON"
if command -v service >/dev/null 2>&1; then
  service cron start 2>/dev/null || service crond start 2>/dev/null || true
fi
echo "[OK] cron registered for agent-admin"

echo

echo "====== SETUP FINISHED ======"
echo "Run app: sudo -iu agent-admin"
echo "Then   : /home/agent-admin/agent-app/bin/run_agent.sh"
echo "Monitor: sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh"
