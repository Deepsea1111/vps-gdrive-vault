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

# Snapshot and sync SQLite databases (avoids "source being updated" errors)
if [[ ${#SQLITE_DBS[@]:-0} -gt 0 ]]; then
    SNAP_DIR="/tmp/gdrive-vault-db-snap"
    mkdir -p "$SNAP_DIR"
    for db_path in "${SQLITE_DBS[@]}"; do
        if [[ -f "$db_path" ]]; then
            db_name=$(basename "$db_path")
            db_dest_dir=$(dirname "$db_path" | sed "s|^/||; s|/|_|g")
            if sqlite3 "$db_path" ".backup '$SNAP_DIR/$db_name'" 2>/dev/null; then
                rclone copy "$SNAP_DIR/$db_name" "${RCLONE_REMOTE}:${GDRIVE_HOT_ROOT}/${db_dest_dir}/" \
                    "${RCLONE_FLAGS[@]}" || log "WARN: $db_name upload failed (non-fatal)"
                log "$db_name synced (from snapshot)"
            else
                log "WARN: $db_name snapshot failed (non-fatal)"
            fi
        fi
    done
    rm -rf "$SNAP_DIR"
fi

# Sync each configured directory
for dir in "${HOT_SYNC_DIRS[@]}"; do
    dir_name=$(basename "$dir")
    log "Syncing $dir -> ${RCLONE_REMOTE}:${GDRIVE_HOT_ROOT}/${dir_name}/"
    rclone sync "$dir/" "${RCLONE_REMOTE}:${GDRIVE_HOT_ROOT}/${dir_name}/" \
        "${EXCLUDE_FLAGS[@]}" \
        "${RCLONE_FLAGS[@]}" || log "WARN: $dir_name sync had errors (non-fatal)"
    log "$dir_name synced"
done

# Summary
COPIED=$(grep -c "Copied" "$LOG_FILE" 2>/dev/null || echo "0")
TRANSFERRED=$(grep "Transferred:" "$LOG_FILE" | grep -oP '[\d.]+ [KMGi]+B' | tail -1 || echo "0 B")
send_summary "$SCRIPT_NAME" $? "$START_TIME" "$(printf 'Files: %s copied\nSize: %s' "$COPIED" "$TRANSFERRED")"
