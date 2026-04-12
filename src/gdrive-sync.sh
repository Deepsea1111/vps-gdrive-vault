#!/bin/bash
# Hot Sync — sync code/configs to Google Drive every 6 hours
# Tuning: Small files -> high checkers, moderate tpslimit
set -euo pipefail

source "$(dirname "$0")/lib.sh"

SCRIPT_NAME="$(basename "$0")"
LOG_FILE="$LOG_DIR/gdrive-sync.log"

RCLONE_FLAGS=(
    --log-file "$LOG_FILE"
    --log-level INFO
    --tpslimit "$HOT_TPSLIMIT"
    --tpslimit-burst 1
    --checkers "$HOT_CHECKERS"
    --transfers "$HOT_TRANSFERS"
    --drive-pacer-min-sleep "$HOT_PACER_SLEEP"
    --fast-list
)

EXCLUDE_FLAGS=()
for pattern in "${GLOBAL_EXCLUDES[@]}"; do
    EXCLUDE_FLAGS+=(--exclude "$pattern")
done

acquire_lock
: > "$LOG_FILE"
START_TIME=$(date +%s)
log "START $SCRIPT_NAME"

# Sync each configured directory
for dir in "${HOT_SYNC_DIRS[@]}"; do
    dir_name=$(basename "$dir")
    log "Syncing $dir -> ${RCLONE_REMOTE}:${GDRIVE_HOT_ROOT}/${dir_name}/"
    rclone sync "$dir/" "${RCLONE_REMOTE}:${GDRIVE_HOT_ROOT}/${dir_name}/" \
        "${EXCLUDE_FLAGS[@]}" \
        "${RCLONE_FLAGS[@]}"
    log "$dir_name synced"
done

# Summary
COPIED=$(grep -c "Copied" "$LOG_FILE" 2>/dev/null || echo "0")
TRANSFERRED=$(grep "Transferred:" "$LOG_FILE" | grep -oP '[\d.]+ [KMGi]+B' | tail -1 || echo "0 B")
send_summary "$SCRIPT_NAME" $? "$START_TIME" "$(printf 'Files: %s copied\nSize: %s' "$COPIED" "$TRANSFERRED")"
