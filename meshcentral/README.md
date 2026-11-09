# MeshCentral — Cockpit-style web console for the Windows PCs

Installed 2026-11-09 on this PC (`Shubham`), MeshCentral **1.3.1** (pinned, `selfUpdate: false`).

**Open:** https://shubham-1.tail5cad5d.ts.net:8443 (or https://100.121.120.45:8443) — from the phone too,
with Tailscale on. The certificate is self-signed, so the browser warns once; accept it.

Gives per machine: remote desktop, terminal (cmd/PowerShell), file browser, processes/services, events,
hardware info, power (sleep/restart/shutdown). Works on Windows 11 Home (which has no RDP host).

## First-time setup (you, not Claude — it's your password)

1. Open the URL → **Create Account**. The first account becomes the site admin.
2. Tell Claude it's done → it runs `lock-signups.ps1` (elevated) so nobody else can sign up.
3. **My Devices → Add Device Group** (e.g. "Home"), then in that group **Add Agent** → Windows →
   download the installer and run it on each PC (this PC, the LLM PC). The PC appears in the list.
   Turn on 2FA under **My Account** if you like.

## Layout

- Install dir `C:\Program Files\MeshCentral` (admin-only); data/certs/db in `meshcentral-data\`.
- Windows service `meshcentral.exe` (auto start). Uses ~0.5 GB RAM.
- Port **8443** HTTPS only (no port-80 redirect). Firewall rule `MeshCentral-8443`: Tailscale
  (`100.64.0.0/10`) + local subnet only. The Intel AMT port 4433 listens but is not opened in the firewall.
- `config.json` here is the template copied into `meshcentral-data\` on install.

## Files

- `install-meshcentral.ps1` — elevated installer (npm install, service, firewall). Re-runnable.
  Gotcha: on PS 5.1 run npm/node via `cmd /c`, and `--install` needs a 2nd run (first one only fetches
  `node-windows`).
- `lock-signups.ps1` — sets `newAccounts: false` and restarts the service.

## Undo

Elevated: `cd "C:\Program Files\MeshCentral"; node node_modules\meshcentral --uninstall`, then delete the
folder and `Remove-NetFirewallRule -Name MeshCentral-8443`. Uninstall agents from each PC's Apps list
("Mesh Agent").
