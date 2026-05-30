#!/usr/bin/env bash

LOG_DIR="/var/log/agent-app"
ARCHIVE_DIR="/var/log/monitor/agent-app/archive"

mkdir -p "$ARCHIVE_DIR"

if [ ! -d "$LOG_DIR" ]; then
    echo "[WARNING] Log directory does not exist: $LOG_DIR"
    exit 0
fi

if [ ! -w "$ARCHIVE_DIR" ]; then
    echo "[WARNING] Archive directory is not writable: $ARCHIVE_DIR"
    exit 0
fi

FOUND_OLD_LOG=0

while IFS= read -r -d '' file; do
    FOUND_OLD_LOG=1
    base=$(basename "$file")
    archive_name="${base}.$(date +%Y%m%d%H%M%S).gz"

    gzip -c "$file" > "$ARCHIVE_DIR/$archive_name"

    if [ $? -eq 0 ]; then
        rm -f "$file"
        echo "[INFO] Archived: $file -> $ARCHIVE_DIR/$archive_name"
    else
        echo "[WARNING] Failed to archive: $file"
    fi
done < <(find "$LOG_DIR" -maxdepth 1 -type f -name "*.log" -mtime +6 -print0)

if [ "$FOUND_OLD_LOG" -eq 0 ]; then
    echo "[INFO] No log files older than 7 days."
fi

FOUND_OLD_ARCHIVE=0

while IFS= read -r -d '' archive; do
    FOUND_OLD_ARCHIVE=1
    rm -f "$archive"
    echo "[INFO] Deleted old archive: $archive"
done < <(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name "*.gz" -mtime +29 -print0)

if [ "$FOUND_OLD_ARCHIVE" -eq 0 ]; then
    echo "[INFO] No archives older than 30 days."
fi
