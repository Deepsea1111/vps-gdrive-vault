#!/bin/bash
# Cold Archive — offload large/old data to Google Drive, free disk space
# Usage: bash cold-archive.sh [--dry-run]
# Tuning: Mixed files -> balanced checkers/transfers
set -euo pipefail

source "$(dirname "$0")/lib.sh"

SCRIPT_NAME="$(basename "$0")"
LOG_FILE="$LOG_DIR/cold-archive.log"
DRY_RUN="${1:-}"

RCLONE_FLAGS=(
    --log-file "$LOG_FILE"
    --log-level INFO
    --tpslimit "$COLD_TPSLIMIT"
    --tpslimit-burst 1
    --checkers "$COLD_CHECKERS"
    --transfers "$COLD_TRANSFERS"
    --drive-pacer-min-sleep "$COLD_PACER_SLEEP"
)

EXCLUDE_FLAGS=()
for pattern in "${GLOBAL_EXCLUDES[@]}"; do
    EXCLUDE_FLAGS+=(--exclude "$pattern")
done

if [[ "$DRY_RUN" == "--dry-run" ]]; then
    RCLONE_FLAGS+=(--dry-run)
fi

acquire_lock
: > "$LOG_FILE"
START_TIME=$(date +%s)
DISK_BEFORE=$(df / | awk 'NR==2 {print $4}')

log "=== COLD ARCHIVE START ${DRY_RUN:+(DRY RUN)} ==="

# Archive each configured directory
for dir in "${COLD_ARCHIVE_DIRS[@]}"; do
    dir_name=$(basename "$dir")
    log "Archiving $dir -> ${RCLONE_REMOTE}:${GDRIVE_ARCHIVE_ROOT}/${dir_name}/"
    rclone sync "$dir/" "${RCLONE_REMOTE}:${GDRIVE_ARCHIVE_ROOT}/${dir_name}/" \
        "${EXCLUDE_FLAGS[@]}" \
        "${RCLONE_FLAGS[@]}" 2>> "$LOG_FILE"
    log "$dir_name archived"
done

# Clean caches (skip in dry-run)
if [[ "$DRY_RUN" != "--dry-run" ]]; then
    log "Cleaning caches..."
    rm -rf /root/.cache/* 2>/dev/null && log "  .cache cleared"
    rm -rf /root/.cargo/registry/{cache,src}/* 2>/dev/null && log "  .cargo cleared"
    go clean -modcache 2>/dev/null && log "  go modcache cleared"
fi

# Summary
DISK_AFTER=$(df / | awk 'NR==2 {print $4}')
FREED_MB=$(( (DISK_AFTER - DISK_BEFORE) / 1024 ))
COPIED=$(grep -c "Copied" "$LOG_FILE" 2>/dev/null || echo "0")

send_summary "$SCRIPT_NAME" $? "$START_TIME" \
    "$(printf 'Files: %s archived\nFreed: %s MB' "$COPIED" "$FREED_MB")"
