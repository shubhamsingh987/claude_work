# claude_work

This repo tracks working files and backups from Claude Code sessions for shubhamsingh987.

## pihole-asterisk-backup-2026-09-14/

Backup + working notes for the Asterisk PBX running on the home Raspberry Pi (hostname `pihole`,
reachable via Raspberry Pi Connect remote shell as user `kudo`).

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

Planned fix: consolidate to a single endpoint definition (keeping the `pbx_ata` naming since it
has qualify monitoring), and remove the dead duplicate `[from-ata]` tune block.

### In progress: PBX greeting
Adding a greeting + beep/chime before the voicebot AGI runs in `from-ht813` and `from-ata`
contexts ("Hello, welcome, you have reached Gangsta's Paradise helpline. Please wait for the
beep..."). Existing usable sound files on the Pi at `/var/lib/asterisk/sounds/en/`:
`beep.gsm`, `beeperr.gsm`, `ascending-2tone.gsm`, `descending-2tone.gsm`. No TTS engine
(flite/festival/espeak) is installed on the Pi; `sox` is available for audio conversion.
Greeting audio is being generated locally (Windows TTS) and transferred over the remote shell.

### Backups
- `pjsip.conf.custom-section.before.txt` / `extensions.conf.custom-section.before.txt` — the
  custom (non-stock-template) portions of both config files, as they stood before any edits,
  captured 2026-09-14. Each file's stock Asterisk sample-config boilerplate is unchanged from
  the 22.10.1 default and is not reproduced here.
- A byte-exact full copy of `/etc/asterisk` also lives **on the Pi itself** at
  `~/asterisk-backup-<timestamp>/asterisk-etc-full/` (created via `cp -a`) — this is the
  authoritative rollback source if an edit needs to be reverted.
- SHA256 checksums of the original files are recorded in the backup file headers.

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
