<p align="center">
  <h1 align="center">VPS GDrive Vault</h1>
  <p align="center">
    Production-grade automated backup system for VPS to Google Drive
    <br />
    <strong>No more 403 errors. No more data loss.</strong>
  </p>
  <p align="center">
    <a href="https://github.com/Deepsea1111/vps-gdrive-vault/blob/main/LICENSE"><img src="https://img.shields.io/github/license/Deepsea1111/vps-gdrive-vault?style=flat-square&color=blue" alt="License"></a>
    <a href="https://github.com/Deepsea1111/vps-gdrive-vault/stargazers"><img src="https://img.shields.io/github/stars/Deepsea1111/vps-gdrive-vault?style=flat-square&color=yellow" alt="Stars"></a>
    <a href="https://github.com/Deepsea1111/vps-gdrive-vault/issues"><img src="https://img.shields.io/github/issues/Deepsea1111/vps-gdrive-vault?style=flat-square" alt="Issues"></a>
    <img src="https://img.shields.io/badge/platform-Linux-lightgrey?style=flat-square&logo=linux" alt="Platform">
    <img src="https://img.shields.io/badge/shell-bash-green?style=flat-square&logo=gnu-bash" alt="Shell">
  </p>
</p>

---

## The Problem

You set up `rclone` to sync your VPS to Google Drive. It works great... until you add a second cron job. Then a third.

Now 3 processes fight over the same API quota. Google returns 403. Each process retries. More 403s. **Nothing ever finishes.**

This is the **Rate Limit Death Spiral** — and this project kills it.

## The Solution

```
                        VPS Server
                            |
        +-------------------+-------------------+
        |                   |                   |
   gdrive-sync.sh      vps-backup.sh      cold-archive.sh
   (Hot Sync)           (Encrypted)        (Cold Archive)
   Every 6 hours        Weekly             Weekly
   Small files          Large chunks       Mixed files
        |                   |                   |
        +--------> SHARED LOCK <--------+
                  (one at a time)
                        |
                  Google Drive
                  (zero 403s)
```

### Three backup tiers, one lock, zero conflicts.

| Tier | Script | Schedule | What | Tuning |
|------|--------|----------|------|--------|
| **Hot** | `gdrive-sync.sh` | Every 6h | Code, configs, databases | `checkers=32` `tpslimit=12` |
| **Encrypted** | `vps-backup.sh` | Sunday 4AM | Full VPS (AES-256, dedup) | `chunk=64M` `transfers=4` |
| **Cold** | `cold-archive.sh` | Monday 2AM | Old data offload + cache cleanup | `checkers=16` `tpslimit=8` |

## Key Features

### Concurrency Control
```bash
# Shared flock — if another backup is running, skip gracefully
LOCKFILE="/tmp/gdrive-operation.lock"
exec 200>"$LOCKFILE"
flock -n 200 || { echo "Another operation running - skipping"; exit 0; }
trap 'flock -u 200; rm -f "$LOCKFILE"' EXIT
```

### Smart Rate Limiting
Not all files are equal. Small source code needs fast checking. Large backup chunks need bandwidth.

```
Small files (code)  --> checkers=32, tpslimit=12, fast-list
Large chunks        --> transfers=4, chunk-size=64M, buffer=128M
Mixed repos         --> checkers=16, tpslimit=8, balanced
```

### Telegram Notifications
Every run sends a clean summary — not raw log spam:

```
+----------------------------------+
| Status                           |
|                                  |
| gdrive-sync.sh                   |
| Files: 135 copied                |
| Size: 1.28 GiB                   |
| Duration: 12m 34s | Errors: 0    |
| Disk: 37G free (82%)             |
+----------------------------------+
```

### SQLite-Safe Database Sync
SQLite databases get modified during sync, causing rclone's `"source file is being updated"` error — which can crash the entire sync script. We solve this with atomic snapshots:

```bash
# In config.env
SQLITE_DBS=(
    "/root/myproject/data.db"
)
```

The hot sync script uses `sqlite3 .backup` to create a consistent snapshot before uploading. If the snapshot or upload fails, it logs a warning and continues — it never kills the sync.

### Encrypted Backups
`restic` provides AES-256 encryption, incremental backups, and deduplication:
```bash
# Backup
restic backup /root/ /var/www/ --tag weekly

# Restore (from anywhere)
restic restore latest --target /

# Browse snapshots
restic snapshots
```

## Quick Start

### 1. Install dependencies

```bash
# Debian/Ubuntu
apt install -y rclone restic curl

# Configure rclone with Google Drive
rclone config
# Create a remote named "gdrive" (or whatever you prefer)
```

### 2. Clone and configure

```bash
git clone https://github.com/Deepsea1111/vps-gdrive-vault.git
cd vps-gdrive-vault

cp config.env.example config.env
nano config.env    # Fill in your paths and settings
```

### 3. Install

```bash
bash install.sh
```

This will:
- Check all dependencies
- Create log directory (`/var/log/rclone/`)
- Set up logrotate (weekly rotation, keep 4 weeks)
- Generate restic encryption password (if needed)
- Show cron configuration

### 4. Test

```bash
# Hot sync (real run — rclone sync is idempotent)
bash src/gdrive-sync.sh

# Cold archive (safe dry-run first)
bash src/cold-archive.sh --dry-run
```

### 5. Schedule

```bash
crontab -e
```

```cron
# Hot sync — every 6 hours
0 */6 * * * /bin/bash /path/to/vps-gdrive-vault/src/gdrive-sync.sh

# Encrypted backup — Sunday 4AM
0 4 * * 0   /bin/bash /path/to/vps-gdrive-vault/src/vps-backup.sh

# Cold archive — Monday 2AM
0 2 * * 1   /bin/bash /path/to/vps-gdrive-vault/src/cold-archive.sh
```

## Configuration

All settings live in `config.env` (never committed to git):

```bash
# rclone remote
RCLONE_REMOTE="gdrive"

# What to sync
HOT_SYNC_DIRS=("/root/myproject" "/var/www/mysite")
COLD_ARCHIVE_DIRS=("/root/old-data")
BACKUP_DIRS=("/root" "/var/www")

# Tuning (adjust if you get 403s or want more speed)
HOT_TPSLIMIT=12        # API requests/sec for hot sync
HOT_CHECKERS=32        # Parallel file comparisons
COLD_TPSLIMIT=8        # Conservative for large dirs

# Telegram (optional)
TELEGRAM_BOT_TOKEN="your-bot-token"
TELEGRAM_CHAT_ID="your-chat-id"
```

See [`config.env.example`](config.env.example) for all options.

## File Structure

```
vps-gdrive-vault/
├── config.env.example       # Configuration template
├── install.sh               # One-command setup
├── src/
│   ├── lib.sh               # Shared: lock, log, notify, summary
│   ├── gdrive-sync.sh       # Tier 1: Hot sync (small files)
│   ├── vps-backup.sh        # Tier 2: Encrypted backup (restic)
│   └── cold-archive.sh      # Tier 3: Cold archive + cleanup
└── configs/
    └── logrotate.conf       # Log rotation config
```

## Tuning Guide

### Getting 403 errors?

Lower your rate limits:
```bash
HOT_TPSLIMIT=8       # was 12
COLD_TPSLIMIT=5      # was 8
```

### Syncs too slow?

If you never hit 403, raise limits:
```bash
HOT_TPSLIMIT=15
HOT_CHECKERS=48
```

### File type reference

| Your workload | Recommended | Why |
|---------------|-------------|-----|
| Thousands of small files | High `checkers` (32-64) | More parallel comparisons |
| Few large files | High `transfers` (4-8) | More parallel uploads |
| Mixed | Balanced (16/2) | Safe middle ground |

### Using Service Accounts (advanced)

For higher API quotas, use Google Cloud Service Accounts:

1. Create GCP project + enable Drive API
2. Create Service Account + download JSON key
3. Share your Drive folder with the SA email
4. Use `--drive-service-account-file` in rclone config
5. Multiple SAs = separate quotas = zero collision

## How It Works

### The Lock Mechanism

All three scripts share one lock file (`/tmp/gdrive-operation.lock`). Using `flock` (kernel-level file locking):

- Script A starts, acquires lock
- Script B starts (via cron), sees lock is held, **exits immediately**
- Script A finishes, lock is released via `trap`
- Next cron cycle, Script B runs normally

Even if Script A crashes, the `trap` ensures cleanup.

### The Staggered Schedule

```
Hour:  0   2   4   6   8  10  12  14  16  18  20  22  24
       |       |   |       |           |           |
       sync    |   backup  sync        sync        sync
              cold
              (Mon only)  (Sun only)
```

Scripts are spread across different hours AND different days. Combined with the lock, overlap is virtually impossible.

## Requirements

| Tool | Version | Purpose |
|------|---------|---------|
| `rclone` | 1.50+ | Google Drive sync |
| `restic` | 0.14+ | Encrypted incremental backups |
| `curl` | any | Telegram notifications |
| `flock` | any | Concurrency control (from `util-linux`) |
| `bash` | 4.0+ | Script runtime |

## Contributing

Contributions welcome! Areas that could use help:

- Support for other cloud providers (S3, Backblaze B2)
- Monitoring dashboard (Grafana/Prometheus metrics)
- More notification channels (Discord, Slack, email)
- Bandwidth throttling for metered connections

## License

[MIT](LICENSE) &copy; 2026 DeepSeaX

---

<p align="center">
  <sub>Born from a real production incident where 3 rclone processes entered a rate limit death spiral. Never again.</sub>
</p>
