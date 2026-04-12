#!/bin/bash
# VPS GDrive Vault — Installer
set -euo pipefail

VAULT_DIR="$(cd "$(dirname "$0")" && pwd)"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "============================================"
echo "  VPS GDrive Vault — Installer"
echo "============================================"
echo ""

# --- 1. Check dependencies ---
echo -e "${YELLOW}Checking dependencies...${NC}"
MISSING=()
for cmd in rclone restic curl flock; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING+=("$cmd")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo -e "${RED}Missing: ${MISSING[*]}${NC}"
    echo "Install with:"
    echo "  apt install -y rclone restic curl util-linux"
    exit 1
fi
echo -e "${GREEN}All dependencies found.${NC}"

# --- 2. Config file ---
echo ""
if [[ ! -f "$VAULT_DIR/config.env" ]]; then
    echo -e "${YELLOW}Creating config.env from example...${NC}"
    cp "$VAULT_DIR/config.env.example" "$VAULT_DIR/config.env"
    echo -e "${RED}IMPORTANT: Edit config.env with your settings before running!${NC}"
    echo "  nano $VAULT_DIR/config.env"
else
    echo -e "${GREEN}config.env exists.${NC}"
fi

# --- 3. Check rclone remote ---
echo ""
source "$VAULT_DIR/config.env"
if rclone listremotes | grep -q "^${RCLONE_REMOTE}:$"; then
    echo -e "${GREEN}rclone remote '$RCLONE_REMOTE' configured.${NC}"
else
    echo -e "${RED}rclone remote '$RCLONE_REMOTE' not found!${NC}"
    echo "Run: rclone config"
    echo "Create a remote named '$RCLONE_REMOTE' for Google Drive."
fi

# --- 4. Create restic password ---
echo ""
if [[ ! -f "$RESTIC_PASSWORD_FILE" ]]; then
    echo -e "${YELLOW}Generating restic password...${NC}"
    openssl rand -base64 32 > "$RESTIC_PASSWORD_FILE"
    chmod 600 "$RESTIC_PASSWORD_FILE"
    echo -e "${RED}SAVE THIS PASSWORD! Stored at: $RESTIC_PASSWORD_FILE${NC}"
    echo "Password: $(cat "$RESTIC_PASSWORD_FILE")"
else
    echo -e "${GREEN}Restic password file exists.${NC}"
fi

# --- 5. Log directory ---
echo ""
mkdir -p "$LOG_DIR"
echo -e "${GREEN}Log directory: $LOG_DIR${NC}"

# --- 6. Logrotate ---
echo ""
LOGROTATE_CONF="/etc/logrotate.d/vps-gdrive-vault"
if [[ ! -f "$LOGROTATE_CONF" ]]; then
    sudo cp "$VAULT_DIR/configs/logrotate.conf" "$LOGROTATE_CONF"
    echo -e "${GREEN}Logrotate installed.${NC}"
else
    echo -e "${GREEN}Logrotate already configured.${NC}"
fi

# --- 7. Set permissions ---
chmod +x "$VAULT_DIR"/src/*.sh

# --- 8. Show cron instructions ---
echo ""
echo "============================================"
echo -e "${GREEN}Installation complete!${NC}"
echo "============================================"
echo ""
echo "Add to crontab (crontab -e):"
echo ""
echo "  # Hot sync — every 6 hours"
echo "  0 */6 * * * /bin/bash $VAULT_DIR/src/gdrive-sync.sh"
echo ""
echo "  # Encrypted backup — Sunday 4AM"
echo "  0 4 * * 0 /bin/bash $VAULT_DIR/src/vps-backup.sh"
echo ""
echo "  # Cold archive — Monday 2AM"
echo "  0 2 * * 1 /bin/bash $VAULT_DIR/src/cold-archive.sh"
echo ""
echo "Test with dry-run first:"
echo "  bash $VAULT_DIR/src/gdrive-sync.sh"
echo "  bash $VAULT_DIR/src/cold-archive.sh --dry-run"
echo ""
