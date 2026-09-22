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
| Samba (file shares) | `\\100.78.206.32\` | ports 445/139 |
| SSH | `ssh pihole` | see root `CLAUDE.md` for setup |

**Not currently working, checked 2026-09-22:**
- **CUPS**: installed, socket listening on 631, but doesn't actually respond — needs
  `sudo systemctl restart cups` (or deeper troubleshooting) before print jobs would work.

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
