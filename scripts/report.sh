#!/usr/bin/env bash
set -u

AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
LOG_FILE="${LOG_FILE:-$AGENT_LOG_DIR/monitor.log}"
START_TIME="${1:-}"
END_TIME="${2:-}"

if [ -f /etc/agent-app.env ]; then
  # shellcheck disable=SC1091
  . /etc/agent-app.env
fi
if [ -f "$AGENT_HOME/.env" ]; then
  # shellcheck disable=SC1090
  . "$AGENT_HOME/.env"
fi

if [ ! -f "$LOG_FILE" ]; then
  echo "[ERROR] Log file not found: $LOG_FILE"
  exit 1
fi

awk -v start="$START_TIME" -v end="$END_TIME" '
function clean_value(v) {
  gsub(/^[A-Z_]+:/, "", v)
  gsub(/%$/, "", v)
  return v + 0
}
function update_stat(name, value, ts) {
  count[name]++
  sum[name] += value
  if (count[name] == 1 || value > max[name]) {
    max[name] = value
    max_ts[name] = ts
  }
  if (count[name] == 1 || value < min[name]) {
    min[name] = value
    min_ts[name] = ts
  }
}
/^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]/ {
  ts = substr($0, 2, 19)
  if (start != "" && ts < start) next
  if (end != "" && ts > end) next

  cpu = mem = disk = ""
  for (i = 1; i <= NF; i++) {
    if ($i ~ /^CPU:/) cpu = clean_value($i)
    if ($i ~ /^MEM:/) mem = clean_value($i)
    if ($i ~ /^DISK_USED:/) disk = clean_value($i)
  }

  if (cpu != "" && mem != "" && disk != "") {
    samples++
    update_stat("CPU", cpu, ts)
    update_stat("Memory", mem, ts)
    update_stat("Disk", disk, ts)
  }
}
END {
  if (samples == 0) {
    print "[ERROR] No matching samples found."
    exit 1
  }

  print "====== STATISTICS REPORT ======"
  names[1] = "CPU"
  names[2] = "Memory"
  names[3] = "Disk"
  for (idx = 1; idx <= 3; idx++) {
    name = names[idx]
    printf "[%s]\n", name
    printf "Average : %.1f%%\n", sum[name] / count[name]
    printf "Maximum : %.1f%% at %s\n", max[name], max_ts[name]
    printf "Minimum : %.1f%% at %s\n", min[name], min_ts[name]
  }
  print "[Samples]"
  printf "Data Points: %d samples\n", samples
}' "$LOG_FILE"
