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
| MediaMTX (CCTV) — RTSP | `rtsp://100.78.206.32:8554` | |
| MediaMTX (CCTV) — HLS | `http://100.78.206.32:8888` | browser-playable |
| MediaMTX (CCTV) — WebRTC | `http://100.78.206.32:8889` | |
| MediaMTX (CCTV) — API | `http://100.78.206.32:9996` | |
| Asterisk (phone/voicebot) | no web UI — SIP only, see `asterisk-pi/` | |
| CUPS (printing) | `http://100.78.206.32:631` | socket-activated — see note below |
| Samba (file shares) | `\\100.78.206.32\` | ports 445/139 |
| SSH | `ssh pihole` | see root `CLAUDE.md` for setup |

**CUPS — actually fixed 2026-09-22** (an earlier note in this file claiming it was already fine
via socket-activation turned out incomplete — see below). Two real issues, both resolved:
1. It's `systemd`-socket-activated with `IdleExitTimeout 60` in `cupsd.conf` — it would start on
   first touch, then **exit again after just 60 seconds idle**, and since `cups.socket` only
   watches the local Unix socket (not TCP 631), a browser hitting `:631` directly could never
   wake it back up — only a local `lp*` command could. Fixed: set `IdleExitTimeout 0` and
   `sudo systemctl enable --now cups.service` so it runs persistently instead of relying on lazy
   activation. Verified alive continuously past the old 60s window.
2. Its access control (`<Location>` blocks in `cupsd.conf`) only had `Allow @LOCAL`, which
   doesn't cover Tailscale's virtual interface — every other service is Tailscale-reachable,
   CUPS wasn't. Fixed: added `Allow 100.64.0.0/10` (Tailscale's CGNAT range) to all four
   `<Location>` blocks (`/`, `/admin`, `/admin/conf`, `/admin/log`). Verified `HTTP 200` from
   both LAN and Tailscale after `sudo systemctl restart cups` (note: `reload` isn't supported by
   this unit, must be `restart`). Backup: `/etc/cups/cupsd.conf.bak.preclaudefix`.

No printers are configured yet (`lpstat -p` → "No destinations added") — that's just nobody
having added one, not a fault.

## CCTV drive — disconnected again (2026-09-23)

The external drive at `/mnt/hdd` (label `cctv`) has **physically dropped off the USB bus a
second time** (first was 2026-09-04, see `asterisk-pi/hdd-watchdog/README.md`) — confirmed via
`lsblk`/`lsusb`: no `sdb` device, no JMicron USB bridge chip present at all. This took both
**MediaMTX** (all 4 ports: RTSP/HLS/WebRTC/API) and **Filebrowser** (its entire serving root IS
`/mnt/hdd`) down at the same moment (23:52:28 IST) — confirmed via kernel log: `I/O error`,
`EXT4-fs ... Remounting filesystem read-only`, `USB disconnect, device number 6`.

**`hdd-watchdog` worked exactly as designed** — detected the unhealthy mount within 5 minutes,
cleanly stopped both dependent services, attempted unmount+fsck, correctly identified the device
is genuinely gone (not just a filesystem error this time), and backed off rather than looping —
this is its documented limitation (physical disconnection needs a human), not a bug. It's been
retrying every 5 minutes since, logging each attempt (`journalctl -t hdd-watchdog`), and will
recover both services automatically the moment the drive physically reconnects.

**This needs your physical attention** — reseat the drive enclosure's USB cable (and check its
power connection if it's externally powered) at the Pi. Once reconnected, no action needed;
the watchdog picks it up within 5 minutes and brings MediaMTX + Filebrowser back on its own.

The watchdog script (`asterisk-pi/hdd-watchdog/hdd-watchdog.sh`) was extended today to also
stop/start `filebrowser` alongside `mediamtx` (previously only handled `mediamtx`) — added
because this exact incident revealed the gap.

**Everything else, re-verified 2026-09-23**: Pi-hole, Homebridge, Netdata, Samba, SSH, Cockpit
(a `curl` test without `-k` for its self-signed cert falsely reported it down — actually fine,
confirmed `HTTP 200` from LAN and Tailscale once tested properly) all genuinely healthy.

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
