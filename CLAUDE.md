# claude_work

This repo tracks working files and backups from Claude Code sessions for shubhamsingh987.

## asterisk-pi/

Config, backups, and setup notes for the Asterisk PBX running on the home Raspberry Pi (hostname
`pihole`, reachable via Raspberry Pi Connect remote shell as user `kudo`). See
[`asterisk-pi/SETUP.md`](asterisk-pi/SETUP.md) for the full how-to-reproduce guide.

### System summary
- Asterisk 22.10.1, built from source (not apt/dpkg-managed), running via systemd (`asterisk.service`).
- Uses **PJSIP** (not legacy chan_sip).
- One physical device: a Grandstream HT813 analog telephone adapter (ATA) at `192.168.1.24`,
  bridging a landline/FXO port into Asterisk.
- Every incoming call is answered and handed to an AI voicebot via
  `AGI(agi_voicebot.py)` at `/var/lib/asterisk/agi-bin/agi_voicebot.py` on the Pi.

### Known issue found (2026-09-14)
`pjsip.conf` defines the **same physical device twice** under two endpoint names —
`ht813` (manually configured, no health monitoring) and `pbx_ata` (an "auto-added" block,
has `qualify_frequency=60` monitoring) — both matching identical source IP `192.168.1.24/32`
via separate `identify` sections. Which one handles an incoming call is undefined/inconsistent.
`extensions.conf` also has two duplicate `[from-ata]` context blocks — one correct (routes to
voicebot), one dead leftover (plays random tune1/2/3 audio, unreachable in normal operation
since FXO calls enter at extension `s`, not a dialed digit pattern).

**Fixed 2026-09-14**: consolidated to the single `pbx_ata` endpoint (kept over `ht813` since it
has qualify monitoring), removed the dead duplicate `[from-ata]` tune block. Verified live via
`pjsip show endpoints` (Objects found: 1) and `dialplan show from-ata`.

### Done: PBX greeting
Every incoming call path now plays a greeting + beep before the voicebot AGI runs ("Hello!
Welcome, you have reached the Gangsta's Paradise helpline. Please wait for the beep to shoot
your query."). Audio generated locally via Windows TTS (`System.Speech.Synthesis`, 8kHz/16-bit
mono), converted to GSM with ffmpeg, installed at
`/var/lib/asterisk/sounds/en/gangsta_greeting.gsm` on the Pi. A copy lives in
`asterisk-pi/sounds/gangsta_greeting.gsm`. Trailing beep uses Asterisk's stock `beep.gsm`.

### Done: CLI socket permissions
`asterisk -rx` now works as `kudo` without `sudo` — set `astctlgroup=kudo` in
`/etc/asterisk/asterisk.conf`'s `[files]` section, then did a full `systemctl stop` +
`start` (a reload alone doesn't recreate the socket). Hit a real gotcha here: the LSB init
script didn't kill the old process cleanly, which left the PBX **fully down** for a few minutes
until forced with a stop+start — see `asterisk-pi/SETUP.md` for the exact recovery steps if it
happens again.

### Config + backups (asterisk-pi/)
- `pjsip.conf.custom-section.before.txt` / `.after.txt` and
  `extensions.conf.custom-section.before.txt` / `.after.txt` — the custom (non-stock-template)
  portions of both config files, before and after the 2026-09-14 fix. Each file's stock
  Asterisk sample-config boilerplate is unchanged from the 22.10.1 default and not reproduced.
- `asterisk.conf.files-section.after.txt` — the `[files]` socket-permission block.
- `sounds/gangsta_greeting.gsm` — the greeting audio.
- `SETUP.md` — full how-to-reproduce-or-restore guide.
- A byte-exact full copy of `/etc/asterisk` (pre-fix) also lives **on the Pi itself** at
  `~/asterisk-backup-<timestamp>/asterisk-etc-full/` (created via `cp -a`) — the authoritative
  rollback source if an edit ever needs to be reverted. On-Pi post-edit backups also exist as
  `*.bak.preclaudefix` next to each live config file.
- SHA256 checksums of the original files are recorded in the "before" backup file headers.

### How to reach the Pi
Via Raspberry Pi Connect remote shell in a browser (no direct SSH tooling was used this
session — driven through browser automation). Terminal input quirk: synthetic Enter/Ctrl
keypresses sent through normal browser automation don't register with this particular
WebRTC/xterm.js terminal; they must be dispatched as real `KeyboardEvent`s via
`document.querySelector('.xterm-helper-textarea')` with `keyCode`/`which` set, e.g.
`new KeyboardEvent('keydown', {key:'Enter', code:'Enter', keyCode:13, which:13, bubbles:true, cancelable:true})`.
Also note: the terminal's scrollback silently drops old content; before reading back any
command output, send `printf '\033[3J\033[H\033[2J'` first to purge scrollback, then run the
command, or output near the buffer's start gets truncated.
