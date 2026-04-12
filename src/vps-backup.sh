#!/bin/bash
# VPS Encrypted Backup — restic + rclone to Google Drive
# Tuning: Large restic chunks -> high transfers, large chunk-size
set -euo pipefail

source "$(dirname "$0")/lib.sh"

SCRIPT_NAME="$(basename "$0")"
LOG_FILE="$LOG_DIR/vps-backup.log"

export RESTIC_REPOSITORY="rclone:${RCLONE_REMOTE}:${GDRIVE_BACKUP_ROOT}"
export RESTIC_PASSWORD_FILE="$RESTIC_PASSWORD_FILE"

# Tune rclone backend for large chunks
export RCLONE_TRANSFERS="$BACKUP_TRANSFERS"
export RCLONE_CHECKERS="$BACKUP_CHECKERS"
export RCLONE_DRIVE_CHUNK_SIZE="$BACKUP_CHUNK_SIZE"
export RCLONE_BUFFER_SIZE="$BACKUP_BUFFER_SIZE"
export RCLONE_LOG_FILE="$LOG_FILE"
export RCLONE_LOG_LEVEL=INFO

acquire_lock
: > "$LOG_FILE"
START_TIME=$(date +%s)

# Init repo if first time
if ! restic snapshots >/dev/null 2>&1; then
    log "Initializing restic repo"
    restic init 2>> "$LOG_FILE"
fi

log "START $SCRIPT_NAME"

# Build exclude flags
EXCLUDE_FLAGS=()
for pattern in "${GLOBAL_EXCLUDES[@]}"; do
    EXCLUDE_FLAGS+=(--exclude="$pattern")
done

# Backup
restic backup "${BACKUP_DIRS[@]}" \
    --exclude="/root/.cache" \
    --exclude="/root/.local/share/Trash" \
    --exclude="node_modules" \
    "${EXCLUDE_FLAGS[@]}" \
    --tag "weekly" \
    --verbose 2>> "$LOG_FILE"

BACKUP_EXIT=$?
log "Backup exit: $BACKUP_EXIT"

# Prune old snapshots
restic forget \
    --keep-weekly "$RESTIC_KEEP_WEEKLY" \
    --keep-monthly "$RESTIC_KEEP_MONTHLY" \
    --prune 2>> "$LOG_FILE"
log "Pruned old snapshots"

# Stats
REPO_SIZE=$(restic stats --mode raw-data 2>/dev/null | grep "Total Size" | awk '{print $3, $4}' || echo "unknown")
SNAP_COUNT=$(restic snapshots --json 2>/dev/null | python3 -c "import json,sys;print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")

send_summary "$SCRIPT_NAME" "$BACKUP_EXIT" "$START_TIME" \
    "$(printf 'Snapshots: %s | Repo: %s' "$SNAP_COUNT" "$REPO_SIZE")"
