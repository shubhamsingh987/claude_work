# pc-remote-off: turn the Windows PC off from the iPhone over Tailscale

This doesn't need the Pi or Claude. The iPhone is on the tailnet and an iOS Shortcut SSHes straight
into the PC. The PC runs OpenSSH Server, reachable only from Tailscale (`100.64.0.0/10`), with **one
key that can only run `pc-power.cmd`** (no shell, no forwarding).

## Setup
1. **iPhone → Shortcuts → New Shortcut → add "Run Script Over SSH".**
   - Host: the PC's Tailscale IP (or MagicDNS name), Port `22`, User: your Windows username
   - Authentication: **SSH Key** → tap the key → **Generate** (ed25519) → **Share Public Key** → send it to the PC
     (AirDrop / Notes / email to yourself)
   - Script: `off`
   - Name the shortcut "PC Off"
2. **On the PC**, in an elevated PowerShell in this folder:
   `powershell -ExecutionPolicy Bypass -File setup-windows.ps1 -PubKey "ssh-ed25519 AAAA..."`
   (it prints the username and Tailscale IP to use in step 1)
3. Duplicate the shortcut with Script `cancel` ("PC Cancel") and `status` ("PC Status").
   Run **PC Status** first as the test: it should reply with the PC's name.

Tailscale must be connected on the phone (it is "On demand" by default).

## Script words
| Script | Effect |
|---|---|
| `off` | shutdown in 60 s |
| `restart` | restart in 60 s |
| `cancel` | abort a pending shutdown/restart (says "Nothing to cancel" if none) |
| `status` | prints the PC name if it's on |

Anything else is refused (only the first word counts, so stray spaces/newlines from the Shortcut are fine).
The command text is never re-parsed by `cmd`, so `&`, `|` or quotes in it can't run anything else. Undo: delete the key's line in `C:\ProgramData\ssh\administrators_authorized_keys`,
`Remove-NetFirewallRule -Name sshd-tailscale-only`, and optionally
`Remove-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0`.
Assumes the Windows user is an administrator (keys then live in `administrators_authorized_keys`).

## Status
**Not yet tested on a real PC or iPhone** (written 2026-11-09). First run: PC Status → PC Off → PC Cancel within 60 s.

## Troubleshooting
- Shortcut times out: Tailscale off on the phone or the PC, or `sshd` not running (`Get-Service sshd`).
- "Permission denied (publickey)": the key line didn't land in `C:\ProgramData\ssh\administrators_authorized_keys`,
  or that file's ACL was changed (only Administrators + SYSTEM may have access, or sshd ignores it). Re-run the setup script.
- Server log: Event Viewer → Applications and Services Logs → OpenSSH → Operational.
