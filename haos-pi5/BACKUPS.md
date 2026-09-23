# HA full backups: where they live

Full Home Assistant backups contain logins and tokens and are hundreds of MB, so they are **not
in git** (GitHub also rejects files over 100 MB). They live in **OneDrive**, outside this repo:

`C:\Users\Singh\OneDrive\HA-Backups\`

This file is the git-side record: what exists, and a checksum so a restore can prove the file is
intact (`sha256sum <file>` in Git Bash must match).

## Encryption key
Backups made through HA's backup system are **encrypted** (`"protected": true` in the tar's
`backup.json`). Restoring needs the **backup encryption key** from HA's "Set up backups" step
(Settings → System → Backups → ⋮ → Encryption key / emergency kit). Keep that key in your password
manager. It is deliberately **not** stored in git or next to the backups.

## Log

| Date (IST) | File | Size | Type | Encrypted | SHA-256 |
|---|---|---|---|---|---|
| 2026-09-23 16:07 | `automatic_backup_2026_9_3_2026-09-23_16.07_22616998.tar` | 317,665,280 B | automatic (HA 2026.9.3, Supervisor 2026.09.2) | yes | `fe2d0faac0224dd82b72aea59e6d3ceb4e35d06dbbbe154e6415cad6d125388c` |
| 2026-07-29 00:14 | `Home_Assistant_Core_2026.7.2_2026-07-29_00.14_20258251.tar` | 21,022,720 B | manual, HA 2026.7.2 | unknown | on the Pi only, not copied; predates nearly everything |

## Adding a new backup
1. HA: Settings → System → Backups → **Backup now** (or let the automatic schedule run).
2. Copy it off the Pi into OneDrive (encrypted, so it's safe there):
   ```bash
   B=<file name from: ssh haos "sudo -n docker run --rm -v /mnt/data/supervisor/backup:/bk:ro alpine ls /bk">
   ssh haos "sudo -n docker run --rm -v /mnt/data/supervisor/backup:/bk:ro alpine cat /bk/$B" \
     > "/c/Users/Singh/OneDrive/HA-Backups/$B"
   sha256sum "/c/Users/Singh/OneDrive/HA-Backups/$B"
   ```
3. Add a row above with the checksum, run `bash haos-pi5/pull_backup.sh`, commit, push.

## Restoring
See [`RESTORE.md`](RESTORE.md) → Option A. On a fresh HAOS onboarding screen choose
**Restore from backup**, upload the `.tar` from OneDrive, enter the encryption key.
