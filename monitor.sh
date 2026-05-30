#!/usr/bin/env bash

AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
LOG_FILE="$AGENT_LOG_DIR/monitor.log"

CPU_LIMIT=20
MEM_LIMIT=10
DISK_LIMIT=80

MAX_SIZE=$((10 * 1024 * 1024))
MAX_FILES=10

rotate_log() {
    if [ -f "$LOG_FILE" ]; then
        size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)

        if [ "$size" -ge "$MAX_SIZE" ]; then
            i=$((MAX_FILES - 1))

            while [ "$i" -ge 1 ]; do
                if [ -f "$LOG_FILE.$i" ]; then
                    mv "$LOG_FILE.$i" "$LOG_FILE.$((i + 1))"
                fi
                i=$((i - 1))
            done

            mv "$LOG_FILE" "$LOG_FILE.1"
            touch "$LOG_FILE"
            chown agent-admin:agent-core "$LOG_FILE" 2>/dev/null || true
            chmod 660 "$LOG_FILE" 2>/dev/null || true
        fi
    fi
}

get_cpu_usage() {
    read -r _ u1 n1 s1 i1 w1 irq1 sirq1 steal1 _ < /proc/stat
    total1=$((u1+n1+s1+i1+w1+irq1+sirq1+steal1))
    idle1=$((i1+w1))

    sleep 0.3

    read -r _ u2 n2 s2 i2 w2 irq2 sirq2 steal2 _ < /proc/stat
    total2=$((u2+n2+s2+i2+w2+irq2+sirq2+steal2))
    idle2=$((i2+w2))

    total_diff=$((total2-total1))
    idle_diff=$((idle2-idle1))

    if [ "$total_diff" -eq 0 ]; then
        echo "0.0"
    else
        awk -v t="$total_diff" -v i="$idle_diff" 'BEGIN { printf "%.1f", (100 * (t - i) / t) }'
    fi
}

compare_float_gt() {
    awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'
}

echo "====== SYSTEM MONITOR RESULT ======"
echo
echo "[HEALTH CHECK]"

PID=$(pgrep -u agent-admin -f "agent_app.py" | head -n 1)

if [ -z "$PID" ]; then
    echo "Checking process 'agent_app.py'... [ERROR]"
    echo "[ERROR] Application process is not running"
    exit 1
fi

echo "Checking process 'agent_app.py'... [OK] (PID: $PID)"

if ss -tulnp | grep -q ":$AGENT_PORT "; then
    echo "Checking port $AGENT_PORT... [OK]"
else
    echo "Checking port $AGENT_PORT... [ERROR]"
    echo "[ERROR] Port $AGENT_PORT is not listening"
    exit 1
fi

echo
echo "[FIREWALL CHECK]"

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    echo "[OK] UFW firewall is active"
elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state 2>/dev/null | grep -q running; then
    echo "[OK] firewalld is active"
else
    echo "[WARNING] UFW/firewalld firewall is not active or cannot be checked"
fi

echo
echo "[RESOURCE MONITORING]"

CPU_USAGE=$(get_cpu_usage)
MEM_USAGE=$(free | awk '/Mem:/ { printf "%.1f", ($3 / $2) * 100 }')
DISK_USED=$(df / | awk 'NR==2 { gsub("%", "", $5); print $5 }')

echo "CPU Usage : ${CPU_USAGE}%"
echo "MEM Usage : ${MEM_USAGE}%"
echo "DISK Used : ${DISK_USED}%"

echo

if compare_float_gt "$CPU_USAGE" "$CPU_LIMIT"; then
    echo "[WARNING] CPU threshold exceeded (${CPU_USAGE}% > ${CPU_LIMIT}%)"
fi

if compare_float_gt "$MEM_USAGE" "$MEM_LIMIT"; then
    echo "[WARNING] MEM threshold exceeded (${MEM_USAGE}% > ${MEM_LIMIT}%)"
fi

if [ "$DISK_USED" -gt "$DISK_LIMIT" ]; then
    echo "[WARNING] DISK threshold exceeded (${DISK_USED}% > ${DISK_LIMIT}%)"
fi

if [ ! -d "$AGENT_LOG_DIR" ]; then
    echo "[ERROR] Log directory does not exist: $AGENT_LOG_DIR"
    exit 1
fi

if [ ! -w "$AGENT_LOG_DIR" ]; then
    echo "[ERROR] Cannot write to log directory: $AGENT_LOG_DIR"
    exit 1
fi

rotate_log

NOW=$(date "+%Y-%m-%d %H:%M:%S")

echo "[$NOW] PID:$PID CPU:${CPU_USAGE}% MEM:${MEM_USAGE}% DISK_USED:${DISK_USED}%" >> "$LOG_FILE"

chown agent-admin:agent-core "$LOG_FILE" 2>/dev/null || true
chmod 660 "$LOG_FILE" 2>/dev/null || true

echo
echo "[INFO] Log appended: $LOG_FILE"
