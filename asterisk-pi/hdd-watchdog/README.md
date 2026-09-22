# hdd-watchdog

Auto-recovery for the CCTV recordings drive on `pihole`.

## Why this exists

On 2026-09-04 the ext4 filesystem on `/mnt/hdd` (external USB drive, label `cctv`, holds
MediaMTX's recordings) hit a corruption error and got kernel-locked into emergency read-only
mode. `mediamtx.service` crashed at the same moment (it was mid-write) and never came back —
the drive then sat broken and unrecorded for **2.5 weeks** before anyone noticed, because
nothing was watching for it. It eventually reappeared on its own (a new USB bridge chip showed
up in `lsusb` — not a manual reseat, cause unknown, possibly an intermittent connection).

This watchdog exists so that never happens silently again: every 5 minutes it checks the mount
is actually healthy (not just "mounted", but *readable*), and if not, walks through the same
recovery steps done manually on 2026-09-22: stop `mediamtx` → unmount → `e2fsck -y` → remount →
restart `mediamtx`.

## Install

```
scp hdd-watchdog.sh pihole:/tmp/
scp hdd-watchdog.service hdd-watchdog.timer pihole:/tmp/
ssh pihole
sudo mv /tmp/hdd-watchdog.sh /usr/local/bin/hdd-watchdog.sh
sudo chmod +x /usr/local/bin/hdd-watchdog.sh
sudo mv /tmp/hdd-watchdog.service /tmp/hdd-watchdog.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now hdd-watchdog.timer
```

## Verify

```
systemctl status hdd-watchdog.timer
systemctl list-timers hdd-watchdog.timer
sudo systemctl start hdd-watchdog.service   # force a run right now
journalctl -t hdd-watchdog -n 50 --no-pager
```

## What it does NOT handle

- **Physical disconnection**: if the drive is actually gone from the USB bus (not just a
  filesystem error), the script logs it and backs off — it can't make a missing device appear.
  Check `lsusb` / `lsblk` by hand in that case.
- **Failing hardware**: repeated recoveries are a sign the drive or its enclosure/cable is
  dying, not that the watchdog is broken. Worth running `smartctl -a /dev/sdb` (installed on
  the Pi as of 2026-09-22) if this fires more than once or twice.
- **Data loss during the corrupted window**: `e2fsck -y` can move damaged inodes into
  `lost+found` or drop them entirely — it repairs the filesystem, it doesn't guarantee every
  file from before the corruption survives.
