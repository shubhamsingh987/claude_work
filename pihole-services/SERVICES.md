# Services on pihole

Reachable via Tailscale from anywhere on the tailnet — no need to be on the home LAN.
Tailscale IP: `100.78.206.32` (MagicDNS: `pihole.tail5cad5d.ts.net`). LAN IP `192.168.1.28`
also works if you're on the home network.

| Service | URL | Notes |
|---|---|---|
| Pi-hole (DNS / ad-block admin) | `http://100.78.206.32/admin` | |
| Homebridge UI | `http://100.78.206.32:8581` | |
| Filebrowser | `http://100.78.206.32:8090` | |
| Cockpit (system admin panel) | `https://100.78.206.32:9090` | full server dashboard — CPU/disk/logs/services |
| **Netdata** (monitoring dashboard) | `http://100.78.206.32:19999` | reinstalled 2026-09-22, includes live Asterisk PJSIP/channel stats — see `asterisk-pi/` |
| MediaMTX (CCTV) — RTSP | `rtsp://100.78.206.32:8554/cam1` | for VLC etc. |
| MediaMTX (CCTV) — HLS | `http://100.78.206.32:8888/cam1/` | browser-playable live view |
| MediaMTX (CCTV) — WebRTC | `http://100.78.206.32:8889/cam1/` | lowest-latency live view |
| MediaMTX (CCTV) — Playback | `http://100.78.206.32:9996/list?path=cam1` | recorded footage (lists segments). Note: 9996 is MediaMTX's *playback* server, not its API — the API isn't enabled (`api:` not set in `mediamtx.yml`). Root paths (`/`) on all MediaMTX ports return 404 by design; use the stream paths above. |
| Asterisk (phone/voicebot) | no web UI — SIP only, see `asterisk-pi/` | |
| CUPS (printing) | `http://100.78.206.32:631` | see note below |
| Samba (file shares) | `\\100.78.206.32\` | ports 445/139 |
| SSH | `ssh pihole` | see root `CLAUDE.md` for setup |

**CUPS — actually fixed 2026-09-22** (an earlier note in this file claiming it was already fine
via socket-activation turned out incomplete — see below). Two real issues, both resolved:
1. It's `systemd`-socket-activated with `IdleExitTimeout 60` in `cupsd.conf` — it would start on
   first touch, then **exit again after just 60 seconds idle**, and since `cups.socket` only
   watches the local Unix socket (not TCP 631), a browser hitting `:631` directly could never
   wake it back up — only a local `lp*` command could. Fixed: set `IdleExitTimeout 0`, and made
   it start at boot via `sudo systemctl add-wants multi-user.target cups.service`. **Gotcha**: a
   plain `systemctl enable cups` does NOT make it start at boot here — its unit file says
   `WantedBy=printer.target`, which only activates when udev sees a physical printer. With no
   printer attached it never starts. (This was initially gotten wrong — `enable --now` looked
   like it worked because `--now` started it immediately, then it was dead again after the next
   reboot.) Verified pulled in by `multi-user.target` via `systemctl list-dependencies`.
2. Its access control (`<Location>` blocks in `cupsd.conf`) only had `Allow @LOCAL`, which
   doesn't cover Tailscale's virtual interface — every other service is Tailscale-reachable,
   CUPS wasn't. Fixed: added `Allow 100.64.0.0/10` (Tailscale's CGNAT range) to all four
   `<Location>` blocks (`/`, `/admin`, `/admin/conf`, `/admin/log`). Verified `HTTP 200` from
   both LAN and Tailscale after `sudo systemctl restart cups` (note: `reload` isn't supported by
   this unit, must be `restart`). Backup: `/etc/cups/cupsd.conf.bak.preclaudefix`.

No printers are configured yet (`lpstat -p` → "No destinations added") — that's just nobody
having added one, not a fault.

## CCTV drive disconnects — root cause found and fixed (2026-09-23)

**Symptom**: the external SSD at `/mnt/hdd` (label `cctv`) dropped off the USB bus twice — first
2026-09-04, then again 2026-09-22 23:52 IST — taking down **MediaMTX** and **Filebrowser** (its
entire serving root IS `/mnt/hdd`) each time. `lsblk`/`lsusb` showed no `sdb` and no JMicron
bridge, so it *looked* like a physical disconnect.

**It wasn't the drive, and it wasn't a loose cable.** Root cause is a known Raspberry Pi 3 USB
limitation (this Pi is a Pi 3 — it uses the old `dwc_otg` USB controller, not the xHCI controller
on Pi 4/5):
- The enclosure is a generic JMicron JMS583 USB→NVMe bridge (`152d:0583`, reports itself as
  "YzWy Disk Device" / "jack88888") that wants to use **UAS** (USB Attached SCSI).
- The kernel logged at every boot: *"The driver for the USB controller dwc_otg_hcd does not
  support scatter-gather which is required by the UAS driver"* — Pi 3's controller can't do UAS.
- Just before the 2026-09-22 disconnect: `dwc_otg_hcd_urb_dequeue: Timed out waiting for FSM NP
  transfer to complete` → `usb 1-1.4: reset` → ~4 min later `USB disconnect`. This happened under
  sustained write load (minutes of MediaMTX "reader is too slow, discarding frames" warnings
  beforehand). On Pi 3, all USB ports **and** Ethernet share one internal hub/USB 2.0 bus.
- Proof it was the controller, not the hardware: a plain reboot re-enumerated the drive
  immediately, and boot-time fsck replayed the journal and reported the filesystem `clean`.

**Fix applied**: added `usb-storage.quirks=152d:0583:u` to `/boot/firmware/cmdline.txt` (the
single-line kernel command line — edited with an exact-byte `diff` check before rebooting; backup
at `/boot/firmware/cmdline.txt.bak.preclaudefix` and `~/cmdline.txt.bak.preclaudefix`). The `u`
flag tells the kernel to never attempt UAS with this device and use plain `usb-storage` (BOT)
instead. Confirmed after reboot: `/proc/cmdline` contains it, and `dmesg` shows *"UAS is ignored
for this device, using usb-storage instead"* / *"Quirks match for vid 152d pid 0583"* — the old
scatter-gather error is gone.

**Speed cost**: expected to be negligible here. Pi 3 is USB 2.0-only (~35–40 MB/s ceiling either
way), and one camera writing sequential 15-minute segments is exactly the low-queue-depth workload
where UAS vs. BOT barely differs. UAS was never actually working on this Pi anyway.

**If it disconnects again anyway**: a reboot has proven sufficient to bring it back (no physical
reseat needed). The real long-term fix is a Pi 4/5 (proper xHCI USB, dedicated bandwidth). Not
yet done: verifying stability over days of recording with the quirk in place — watch
`journalctl -t hdd-watchdog` and `dmesg | grep -i 'usb 1-1.4'` for resets.

**`hdd-watchdog` behaved correctly throughout** — detected the dead mount within 5 minutes,
stopped the dependent services, correctly recognized the device was absent, and backed off to
retry every 5 minutes rather than looping. It was extended during this incident to also manage
`filebrowser` (previously `mediamtx`-only).

**Side finding**: the Pi also rebooted itself at 2026-09-22 14:53 IST (`who -b`), which wasn't
noticed at the time and is not explained by anything done in this session. Unrelated to the
23:52 disconnect (9 hours apart), but worth watching for — check `journalctl --list-boots` if
uptime looks unexpectedly short.

**All services re-verified after the fix (2026-09-23, from both LAN and Tailscale)**: Pi-hole,
Homebridge, Filebrowser, Cockpit, Netdata, CUPS, MediaMTX (live HLS/WebRTC `cam1` streams and
the playback server all `HTTP 200`; RTSP port open), Samba, SSH — all healthy. Recording
resumed (new segments landing in `/mnt/hdd/recordings/cam1/`), Asterisk's `pbx_ata` endpoint
`Avail`. (Cockpit uses a self-signed cert — test with `curl -k`, otherwise it falsely looks down.)

## Whole Pi offline (2026-09-23, ~01:00 IST)

Later the same night, `pihole` dropped off the network entirely: no ping on LAN (`192.168.1.28`),
no ARP entry, Tailscale showing it `offline, last seen 4h ago`. Not reachable any way remotely —
needs a physical check / power-cycle. Unconfirmed guess worth checking once it's back: the
repeated USB drive dropouts plus a full crash can both be symptoms of an undersized power supply
on this Pi 3 (bus-powered HDD); `vcgencmd get_throttled` (non-zero = under-voltage seen) and
`journalctl -b -1 -k | grep -i voltage` after it boots will say. LAN DNS kept working because
clients use the router (`192.168.1.1`), not Pi-hole directly.

## Auto-restart hardening (2026-09-22)

See [`systemd-overrides/`](systemd-overrides/) — drop-in overrides adding/widening restart
policy on `asterisk`, `mediamtx`, `homebridge`, `filebrowser`. Backstory: `mediamtx` already had
`Restart=always`, but systemd's default crash-loop protection
(`StartLimitBurst=5` within `StartLimitIntervalSec=10`) meant a burst of failures made it give
up restarting **permanently** — which is exactly what happened during the 2026-09-04 CCTV drive
corruption (see `asterisk-pi/hdd-watchdog/README.md`). `asterisk.service` (LSB-generated) had no
restart policy at all (`Restart=no`). Installed on the Pi and verified live via
`systemctl show <service> -p Restart -p StartLimitBurst`.

This complements (doesn't replace) `asterisk-pi/hdd-watchdog/` — a plain restart doesn't fix a
genuinely broken/disconnected drive, which is what that watchdog handles specifically.
