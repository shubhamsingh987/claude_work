# pc-remote-off — turn the Windows PC off from a phone/Claude session over Tailscale

Cloud Claude sessions are **not** on the tailnet, so the command runs from `pihole` (always on, on
the tailnet). Start a Remote Control session there and drive it from the Claude app:
`ssh pihole` → `claude remote-control` (Claude Code must be installed on the Pi).

The PC gets OpenSSH Server, reachable only from `100.64.0.0/10`, with **one key that can only run
`pc-power.cmd`** (no shell, no forwarding).

## Setup
1. On the Pi: `bash setup-pi.sh <pc-tailscale-ip> <windows-user>` → copy the printed public key.
2. On the PC, elevated PowerShell, in this folder:
   `powershell -ExecutionPolicy Bypass -File setup-windows.ps1 -PubKey "ssh-ed25519 AAAA... pi-pc-off"`
3. Test from the Pi: `ssh pc-off status`

## Use (from the Pi / a Remote Control session on it)
| Command | Effect |
|---|---|
| `ssh pc-off off` | shutdown in 60 s |
| `ssh pc-off restart` | restart in 60 s |
| `ssh pc-off cancel` | abort a pending shutdown |
| `ssh pc-off status` | prints the PC name if it's on |

Undo: `Remove-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0`, delete the line from
`C:\ProgramData\ssh\administrators_authorized_keys`, `Remove-NetFirewallRule -Name sshd-tailscale-only`.
Assumes the Windows user is an administrator (keys then live in `administrators_authorized_keys`).
