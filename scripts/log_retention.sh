#!/usr/bin/env bash
set -u

AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
ARCHIVE_DIR="${ARCHIVE_DIR:-/var/log/monitor/agent-app/archive}"
COMPRESS_AFTER_DAYS="${COMPRESS_AFTER_DAYS:-7}"
DELETE_AFTER_DAYS="${DELETE_AFTER_DAYS:-30}"

if [ ! -d "$AGENT_LOG_DIR" ]; then
  echo "[WARNING] Log directory does not exist: $AGENT_LOG_DIR"
  exit 0
fi

mkdir -p "$ARCHIVE_DIR" 2>/dev/null || {
  echo "[WARNING] Cannot create archive directory: $ARCHIVE_DIR"
  exit 0
}

if [ ! -w "$ARCHIVE_DIR" ]; then
  echo "[WARNING] Archive directory is not writable: $ARCHIVE_DIR"
  exit 0
fi

found=0
while IFS= read -r -d '' file; do
  found=1
  base="$(basename "$file")"
  stamp="$(date '+%Y%m%d%H%M%S')"
  target="$ARCHIVE_DIR/${base}.${stamp}.gz"

  if gzip -c "$file" > "$target"; then
    rm -f "$file"
    echo "[INFO] Archived: $file -> $target"
  else
    rm -f "$target"
    echo "[WARNING] Failed to archive: $file"
  fi
done < <(find "$AGENT_LOG_DIR" -maxdepth 1 -type f -name '*.log' -mtime +$((COMPRESS_AFTER_DAYS - 1)) -print0 2>/dev/null)

if [ "$found" -eq 0 ]; then
  echo "[INFO] No log files older than ${COMPRESS_AFTER_DAYS} days."
fi

deleted=0
while IFS= read -r -d '' gzfile; do
  deleted=1
  rm -f "$gzfile" && echo "[INFO] Deleted old archive: $gzfile"
done < <(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name '*.gz' -mtime +$((DELETE_AFTER_DAYS - 1)) -print0 2>/dev/null)

if [ "$deleted" -eq 0 ]; then
  echo "[INFO] No archives older than ${DELETE_AFTER_DAYS} days."
fi

exit 0
