# Remote shutdown for this PC (`Shubham`, Tailscale 100.121.120.45)

Lets another Claude session (or any machine holding the key) shut this Windows PC down over SSH.
Set up 2026-11-09.

## Use it

```
ssh shubham-pc shutdown   # shuts down in 60 s
ssh shubham-pc restart    # restarts in 60 s
ssh shubham-pc cancel     # aborts a pending shutdown/restart
ssh shubham-pc status     # harmless check
```

`~/.ssh/config` alias (add it on the calling machine):

```
Host shubham-pc
    HostName 100.121.120.45
    User singh
    IdentityFile ~/.ssh/id_ed25519_shutdown_shubham
    IdentitiesOnly yes
```

The private key is `C:\Users\singh\.ssh\id_ed25519_shutdown_shubham` on this PC. To let another machine use
it, copy that file (and the `.pub`) into the other machine's `~/.ssh/` (chmod 600 on Linux).

## Set it up on the iPhone (one-tap shutdown)

The phone gets its **own** key (don't copy the PC's private key to the phone).

1. Install **Tailscale** on the phone and sign in to the same tailnet (`tail5cad5d.ts.net`). Turn it on.
2. Open **Shortcuts** → **+** → add the action **Run Script Over SSH**. Fill in:
   - Host: `100.121.120.45`  · Port: `22`  · User: `singh`
   - Authentication: **SSH Key** → tap the key → **ed25519** → **Copy Public Key**.
   - Script: `shutdown`
3. Send that public key (starts with `ssh-ed25519 ...`) to Claude in this session (or any session on this PC).
   Claude adds it to `C:\ProgramData\ssh\administrators_authorized_keys` with the same
   `restrict,command="..."` lock as the PC key (needs one UAC click on the PC).
4. Name the shortcut "Shut down PC". Optional: make a second one with Script `cancel`.
5. Test first with Script `status` — it should reply `OK: SHUBHAM is up ...`.

Alternative: an SSH app (Termius, Blink) with its own generated ed25519 key — same step 3, then run `shutdown`.

## What it can and can't do

- The key is in `C:\ProgramData\ssh\administrators_authorized_keys` with
  `restrict,command="... claude-power.ps1"`: whatever command is sent, only `claude-power.ps1` runs. It
  understands `shutdown`, `restart`, `cancel`; anything else prints status. No shell, no port forwarding.
- `sshd_config`: `PasswordAuthentication no`. Firewall rule `OpenSSH-Server-In-TCP` only allows
  Tailscale (`100.64.0.0/10`) and the local subnet.
- Backups made by setup: `sshd_config.bak-preclaude` (and `administrators_authorized_keys.bak-preclaude`
  if one existed) in `C:\ProgramData\ssh\`.

## Files

- `claude-power.ps1` — the forced command (installed to `C:\ProgramData\ssh\`, admin-only writable).
- `setup-sshd.ps1` — elevated installer (OpenSSH Server capability, key, config, firewall). Re-runnable.

## Undo

Elevated: `Stop-Service sshd; Set-Service sshd -StartupType Disabled`, or remove the `claude-shutdown@`
line from `administrators_authorized_keys`.
