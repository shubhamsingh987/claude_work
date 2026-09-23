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
recovery steps done manually on 2026-09-14: stop `mediamtx` + `filebrowser` → unmount →
`e2fsck -y` → remount → restart both.

**Second incident, 2026-09-23**: the drive disconnected again (physically gone from the USB bus
— confirmed via `lsblk`/`lsusb`, not just a filesystem error this time). The watchdog worked
exactly as intended: detected it within 5 minutes, cleanly stopped both dependent services,
correctly identified the device was truly absent, and backed off to retry every 5 minutes rather
than looping pointlessly — see "What it does NOT handle" below, this is by design. This incident
is also what revealed `filebrowser` needed the same treatment as `mediamtx` (its serving root IS
`/mnt/hdd` — it was going down at the same moment but nothing was bringing it back up), so the
script was extended to handle both. See `pihole-services/SERVICES.md` for live status.

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

- **Device gone from the USB bus**: if the drive disappears from `lsusb`/`lsblk` entirely (not
  just a filesystem error), the script logs it and backs off — it can't make a missing device
  appear. **On this Pi, that has so far meant a wedged USB controller, not a loose cable**: the
  Pi 3's `dwc_otg` controller can't do UAS and hung under write load; a plain `sudo reboot`
  brought the drive straight back. A kernel quirk disabling UAS for this enclosure was applied
  on 2026-09-23 to stop it happening — see `pihole-services/SERVICES.md`, "CCTV drive
  disconnects". The watchdog deliberately does NOT reboot the Pi itself (that would also take
  down DNS, the phone line, etc.) — that's a human decision.
- **Failing hardware**: repeated recoveries are a sign the drive or its enclosure/cable is
  dying, not that the watchdog is broken. Worth running `smartctl -a /dev/sdb` (installed on
  the Pi as of 2026-09-22) if this fires more than once or twice.
- **Data loss during the corrupted window**: `e2fsck -y` can move damaged inodes into
  `lost+found` or drop them entirely — it repairs the filesystem, it doesn't guarantee every
  file from before the corruption survives.
