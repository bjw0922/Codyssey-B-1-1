#!/usr/bin/env bash
set -u

AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
LOG_FILE="${LOG_FILE:-$AGENT_LOG_DIR/monitor.log}"
LOG_MAX_BYTES="${LOG_MAX_BYTES:-10485760}"
LOG_KEEP="${LOG_KEEP:-10}"
APP_PATTERN="${APP_PATTERN:-agent_app.py|agent-app-linux-x86|agent-app-linux-arm64|/home/agent-admin/agent-app/agent-app}"
CPU_LIMIT="${CPU_LIMIT:-20}"
MEM_LIMIT="${MEM_LIMIT:-10}"
DISK_LIMIT="${DISK_LIMIT:-80}"

if [ -f /etc/agent-app.env ]; then
  # shellcheck disable=SC1091
  . /etc/agent-app.env
fi
if [ -f "$AGENT_HOME/.env" ]; then
  # shellcheck disable=SC1090
  . "$AGENT_HOME/.env"
fi

print_header() {
  echo "====== SYSTEM MONITOR RESULT ======"
  echo
}

fail_exit() {
  echo "[ERROR] $1"
  exit 1
}

ensure_log_dir() {
  if [ ! -d "$AGENT_LOG_DIR" ]; then
    mkdir -p "$AGENT_LOG_DIR" 2>/dev/null || fail_exit "Cannot create log directory: $AGENT_LOG_DIR"
  fi
  if [ ! -w "$AGENT_LOG_DIR" ]; then
    fail_exit "Log directory is not writable: $AGENT_LOG_DIR"
  fi
  touch "$LOG_FILE" 2>/dev/null || fail_exit "Cannot write log file: $LOG_FILE"
}

rotate_log_if_needed() {
  [ -f "$LOG_FILE" ] || return 0

  size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
  if [ "$size" -lt "$LOG_MAX_BYTES" ]; then
    return 0
  fi

  i=$((LOG_KEEP - 1))
  while [ "$i" -ge 1 ]; do
    if [ -f "$LOG_FILE.$i" ]; then
      mv -f "$LOG_FILE.$i" "$LOG_FILE.$((i + 1))"
    fi
    i=$((i - 1))
  done

  mv -f "$LOG_FILE" "$LOG_FILE.1"
  touch "$LOG_FILE"
  echo "[INFO] Log rotated: $LOG_FILE.1"
}

find_app_pid() {
  pgrep -f "$APP_PATTERN" 2>/dev/null | grep -v "^$$$" | head -n 1
}

check_port() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | awk -v port=":$AGENT_PORT" '$1 == "LISTEN" && $4 ~ port"$" { found=1 } END { exit found ? 0 : 1 }'
    return $?
  fi

  if command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null | awk -v port=":$AGENT_PORT" '$6 == "LISTEN" && $4 ~ port"$" { found=1 } END { exit found ? 0 : 1 }'
    return $?
  fi

  return 1
}

check_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    if ufw status 2>/dev/null | grep -qi "Status: active"; then
      echo "[OK] UFW firewall is active"
      return 0
    fi
  fi

  if command -v firewall-cmd >/dev/null 2>&1; then
    if firewall-cmd --state 2>/dev/null | grep -qi "running"; then
      echo "[OK] firewalld is active"
      return 0
    fi
  fi

  echo "[WARNING] UFW/firewalld firewall is not active or cannot be checked"
  return 0
}

read_cpu_line() {
  awk '/^cpu / {print $2, $3, $4, $5, $6, $7, $8, $9}' /proc/stat
}

get_cpu_usage() {
  read -r u1 n1 s1 i1 w1 irq1 sirq1 steal1 <<< "$(read_cpu_line)"
  idle1=$((i1 + w1))
  total1=$((u1 + n1 + s1 + i1 + w1 + irq1 + sirq1 + steal1))

  sleep 1

  read -r u2 n2 s2 i2 w2 irq2 sirq2 steal2 <<< "$(read_cpu_line)"
  idle2=$((i2 + w2))
  total2=$((u2 + n2 + s2 + i2 + w2 + irq2 + sirq2 + steal2))

  total_diff=$((total2 - total1))
  idle_diff=$((idle2 - idle1))

  if [ "$total_diff" -le 0 ]; then
    echo "0.0"
  else
    awk -v total="$total_diff" -v idle="$idle_diff" 'BEGIN { printf "%.1f", (100 * (total - idle) / total) }'
  fi
}

get_mem_usage() {
  free | awk '/^Mem:/ { printf "%.1f", ($3 / $2) * 100 }'
}

get_disk_usage() {
  df -P / | awk 'NR==2 { gsub("%", "", $5); print $5 }'
}

print_header
ensure_log_dir
rotate_log_if_needed

PID="$(find_app_pid || true)"

echo "[HEALTH CHECK]"
if [ -n "$PID" ]; then
  echo "Checking process 'agent_app.py / agent-app'... [OK] (PID: $PID)"
else
  echo "Checking process 'agent_app.py / agent-app'... [FAIL]"
  fail_exit "Application process is not running"
fi

if check_port; then
  echo "Checking port $AGENT_PORT... [OK]"
else
  echo "Checking port $AGENT_PORT... [FAIL]"
  fail_exit "TCP port $AGENT_PORT is not LISTEN state"
fi

echo

echo "[FIREWALL CHECK]"
check_firewall

echo

echo "[RESOURCE MONITORING]"
CPU_USAGE="$(get_cpu_usage)"
MEM_USAGE="$(get_mem_usage)"
DISK_USED="$(get_disk_usage)"

echo "CPU Usage : $CPU_USAGE%"
echo "MEM Usage : $MEM_USAGE%"
echo "DISK Used  : $DISK_USED%"

echo

awk -v v="$CPU_USAGE" -v limit="$CPU_LIMIT" 'BEGIN { exit (v > limit) ? 0 : 1 }' && echo "[WARNING] CPU threshold exceeded ($CPU_USAGE% > $CPU_LIMIT%)"
awk -v v="$MEM_USAGE" -v limit="$MEM_LIMIT" 'BEGIN { exit (v > limit) ? 0 : 1 }' && echo "[WARNING] MEM threshold exceeded ($MEM_USAGE% > $MEM_LIMIT%)"
awk -v v="$DISK_USED" -v limit="$DISK_LIMIT" 'BEGIN { exit (v > limit) ? 0 : 1 }' && echo "[WARNING] DISK threshold exceeded ($DISK_USED% > $DISK_LIMIT%)"

NOW="$(date '+%Y-%m-%d %H:%M:%S')"
printf '[%s] PID:%s CPU:%s%% MEM:%s%% DISK_USED:%s%%\n' "$NOW" "$PID" "$CPU_USAGE" "$MEM_USAGE" "$DISK_USED" >> "$LOG_FILE"

echo "[INFO] Log appended: $LOG_FILE"
exit 0
