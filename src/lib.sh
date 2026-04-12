#!/bin/bash
# Shared library for VPS GDrive Vault scripts

# Load config
VAULT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${VAULT_DIR}/config.env"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: config.env not found. Run: cp config.env.example config.env"
    exit 1
fi
source "$CONFIG_FILE"

# Ensure log dir exists
mkdir -p "$LOG_DIR"

# --- Shared Lock ---
acquire_lock() {
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        echo "$(date): Another gdrive operation running - skipping"
        exit 0
    fi
    trap 'flock -u 200; rm -f "$LOCK_FILE"' EXIT
}

# --- Logging ---
log() {
    echo "[$(date -u '+%Y-%m-%dT%H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# --- Telegram Notification ---
notify() {
    local msg="$1"
    if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
        curl -s -G -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
            --data-urlencode "text=${msg}" \
            --data-urlencode "disable_web_page_preview=true" > /dev/null 2>&1
    fi
}

# --- Summary helper ---
send_summary() {
    local script_name="$1"
    local exit_code="$2"
    local start_time="$3"
    local extra_info="$4"

    local end_time=$(date +%s)
    local duration=$(( end_time - start_time ))
    local mins=$(( duration / 60 ))
    local secs=$(( duration % 60 ))
    local disk_info=$(df -h / | awk 'NR==2 {print $4 " free (" $5 ")"}')
    local error_count=$(grep -c "ERROR" "$LOG_FILE" 2>/dev/null || echo "0")

    if [[ "$exit_code" -ne 0 || "$error_count" -gt 0 ]]; then
        local msg=$(printf "❌ [%s] %s FAILED\nErrors: %s\nDuration: %dm %ds\nDisk: %s" \
            "$(hostname)" "$script_name" "$error_count" "$mins" "$secs" "$disk_info")
        notify "$msg"
        log "FAILED ($error_count errors)"
    else
        local msg=$(printf "✅ [%s] %s\n%s\nDuration: %dm %ds | Errors: 0\nDisk: %s" \
            "$(hostname)" "$script_name" "$extra_info" "$mins" "$secs" "$disk_info")
        notify "$msg"
        log "DONE (${mins}m ${secs}s)"
    fi
}
