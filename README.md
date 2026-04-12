# VPS GDrive Vault

Production-grade automated backup system for VPS to Google Drive. Built to prevent API Rate Limits (403 errors) and handle concurrency safely.

Born from real-world pain: 3 backup scripts running simultaneously hit Google Drive's rate limit, entering a "Death Spiral" of infinite retries. This project solves that with smart scheduling, shared locking, and per-workload tuning.

## Features

- **3-Tier Backup Architecture** — Hot sync, encrypted backup, cold archive
- **Rate Limit Prevention** — Pre-tuned `rclone` flags per file pattern (no more 403 errors)
- **Concurrency Lock** — Shared `flock` ensures only one backup runs at a time
- **Telegram Notifications** — Parsed summary after each run (not raw log spam)
- **Encrypted Backups** — `restic` with AES-256, incremental, deduplicated
- **Log Management** — Built-in `logrotate` prevents disk exhaustion
- **Staggered Scheduling** — Cron jobs designed to never overlap

## Architecture

```
VPS Server
  |
  |-- gdrive-sync.sh (Hot)          Every 6 hours
  |   Small files: code, configs     tpslimit=12, checkers=32
  |   -> gdrive:GitGDrive/
  |
  |-- vps-backup.sh (Encrypted)     Weekly (Sunday)
  |   Full VPS via restic            transfers=4, chunk=64M
  |   -> gdrive:VPS-Backup/
  |
  |-- cold-archive.sh (Cold)        Weekly (Monday)
  |   Large/old data offload         tpslimit=8, checkers=16
  |   -> gdrive:GitGDrive/archive/
  |
  +-- Shared flock (/tmp/gdrive-operation.lock)
      Only ONE script runs at a time
```

## Why Tuning Matters

Google Drive API has a per-project rate limit. Without tuning, `rclone` fires unlimited requests — fine for 100 files, death spiral for 100,000.

| Workload | tpslimit | checkers | transfers | Why |
|----------|----------|----------|-----------|-----|
| Small files (code) | 12 | 32 | 4 | High checkers = fast comparison, moderate API rate |
| Large chunks (restic) | - | 4 | 4 | Bandwidth matters, fewer API calls per file |
| Mixed (repos) | 8 | 16 | 2 | Conservative — complex directory trees |

## Quick Start

```bash
# 1. Clone
git clone https://github.com/Deepsea1111/vps-gdrive-vault.git
cd vps-gdrive-vault

# 2. Configure
cp config.env.example config.env
nano config.env    # Fill in your paths, rclone remote, Telegram bot

# 3. Install
bash install.sh

# 4. Test (dry-run)
bash src/gdrive-sync.sh
bash src/cold-archive.sh --dry-run

# 5. Add to crontab (crontab -e)
0 */6 * * * /bin/bash /path/to/vps-gdrive-vault/src/gdrive-sync.sh
0 4 * * 0   /bin/bash /path/to/vps-gdrive-vault/src/vps-backup.sh
0 2 * * 1   /bin/bash /path/to/vps-gdrive-vault/src/cold-archive.sh
```

## Prerequisites

- `rclone` (configured with Google Drive remote)
- `restic` (for encrypted backups)
- `curl` (for Telegram notifications)
- `flock` (from `util-linux`, usually pre-installed)

```bash
apt install -y rclone restic curl
```

## Telegram Notifications

Each script sends a parsed summary (not raw logs):

```
✅ [myserver] gdrive-sync.sh
Files: 135 copied
Size: 1.28 GiB
Duration: 12m 34s | Errors: 0
Disk: 37G free (82%)
```

Failed runs send alerts:

```
❌ [myserver] vps-backup.sh FAILED
Errors: 3
Duration: 2m 10s
Disk: 37G free (82%)
```

Set `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` in `config.env`. Leave empty to disable.

## File Structure

```
vps-gdrive-vault/
├── config.env.example    # Template — copy to config.env
├── install.sh            # Auto-setup: deps, dirs, logrotate
├── LICENSE               # MIT
├── README.md
├── src/
│   ├── lib.sh            # Shared: lock, log, notify, summary
│   ├── gdrive-sync.sh    # Hot sync (small files)
│   ├── vps-backup.sh     # Encrypted backup (restic)
│   └── cold-archive.sh   # Cold archive (large data)
└── configs/
    └── logrotate.conf    # Weekly rotation, keep 4, compress
```

## The Rate Limit Death Spiral (Why This Exists)

When multiple `rclone` processes run simultaneously against Google Drive:

1. All processes share the same API quota
2. They exceed the rate limit -> 403 errors
3. Each process retries immediately -> more 403s
4. Google throttles harder -> retry loops slow to ~500ms each
5. **No process ever finishes** because they keep stealing quota from each other

This project prevents it with:
- **Shared lock** — only one process at a time
- **Staggered cron** — scripts scheduled hours apart
- **tpslimit** — hard cap on API requests per second
- **drive-pacer-min-sleep** — Google Drive specific rate limiter

## Customization

### Adding more sync directories

Edit `config.env`:

```bash
HOT_SYNC_DIRS=(
    "/root/project-a"
    "/root/project-b"
    "/var/www/mysite"
)
```

### Adjusting rate limits

If you still get 403 errors, lower `tpslimit`:

```bash
HOT_TPSLIMIT=8      # was 12
COLD_TPSLIMIT=5     # was 8
```

If syncs are too slow and you never hit 403, raise them:

```bash
HOT_TPSLIMIT=15
HOT_CHECKERS=48
```

### Using Service Accounts

For higher quotas, use Google Cloud Service Accounts:

1. Create a GCP project, enable Drive API
2. Create Service Account, download JSON key
3. Share your Drive folder with the SA email
4. Configure rclone: `rclone config` -> choose Service Account

Multiple SAs = separate quotas = no collision.

## License

MIT
