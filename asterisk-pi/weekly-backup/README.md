# weekly-backup

Weekly config/state backup for `pihole`, installed 2026-10-18. `weekly-backup.timer` fires Sundays 03:30
(`Persistent=true`, so a missed run happens at next boot); `weekly-backup.sh` writes
`/mnt/hdd/backups/weekly/pihole-YYYY-MM-DD.tar.gz` (+ `.sha256`) and keeps the newest 4. Contents: `/etc`,
`/home/kudo`, `/usr/local`, the Checkmk agent files, `cmdline.txt`/`config.txt`, `/var/lib/{asterisk,tailscale,homebridge}`,
`/opt/homebridge/start.sh`, plus a `dpkg --get-selections` list (node_modules/caches excluded). First run: 273 MB, ~3 min.
It aborts if `/mnt/hdd` is not mounted. Check with `journalctl -t weekly-backup`.

**Not an off-box backup** — it lives on the same SSD as the OS. The user declined copying it to the PC (2026-10-18).

Install: `scp` the three files over, **strip CRs** (`sed -i 's/\r$//'`), `install -m755` the script to
`/usr/local/bin/`, the unit files to `/etc/systemd/system/`, then `systemctl enable --now weekly-backup.timer`.
Restore: unpack with `tar xzf <file> -C /` (review first; Tailscale state and SSH keys come back with it).
