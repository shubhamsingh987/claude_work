# Asterisk PBX setup — pihole

How the Asterisk PBX on the home Raspberry Pi (hostname `pihole`, user `kudo`) is wired up,
and how to reproduce or restore this configuration.

## Hardware / topology

- Raspberry Pi running Asterisk 22.10.1, built from source (not an apt package).
- One physical device: a **Grandstream HT813** analog telephone adapter (ATA) at
  `192.168.1.24`, bridging a landline/FXO port into Asterisk over SIP (PJSIP).
- Every incoming call is answered, plays a greeting + beep, then hands off to an AI
  voicebot via AGI: `/var/lib/asterisk/agi-bin/agi_voicebot.py`.

## Reaching the box

Via [Raspberry Pi Connect](https://connect.raspberrypi.com) remote shell in a browser (device
must be registered with `rpi-connect` and signed in with the owner's Raspberry Pi ID) — or
plain SSH if you have network access to it directly.

## 1. Install Asterisk

Already done on this box (built from source under `/usr/sbin/asterisk`, config in
`/etc/asterisk/`, runs via systemd unit `asterisk.service`, an LSB-generated wrapper around
`/etc/init.d/asterisk`). To reproduce elsewhere, follow the standard Asterisk source build
(`./configure && make && make install && make samples`).

## 2. PJSIP endpoint for the HT813

Drop this into `/etc/asterisk/pjsip.conf` (see `pjsip.conf.custom-section.after.txt` in this
folder for the exact block):

```
[global]
type=global
endpoint_identifier_order=ip,username,anonymous
[transport-udp]
type=transport
protocol=udp
bind=0.0.0.0
[pbx_ata]
type=endpoint
context=from-ata
disallow=all
allow=ulaw
allow=alaw
aors=pbx_ata-aor
direct_media=no
[pbx_ata-aor]
type=aor
contact=sip:192.168.1.24:5060
qualify_frequency=60
[pbx_ata-identify]
type=identify
endpoint=pbx_ata
match=192.168.1.24/32
```

**Important**: define the physical device under **one** endpoint name only. An earlier version
of this config had it duplicated under both `ht813` and `pbx_ata` with identical IP match
criteria, which made call routing undefined. Keep `qualify_frequency` set so `pjsip show
endpoints` actually reports reachability instead of `NonQual`.

## 3. Dialplan

In `/etc/asterisk/extensions.conf` (see `extensions.conf.custom-section.after.txt`):

```
[from-ata]
exten => s,1,NoOp(Incoming FXO call from ATA - routing to voicebot)
 same => n,Answer()
 same => n,Playback(gangsta_greeting)
 same => n,Playback(beep)
 same => n,AGI(agi_voicebot.py)
 same => n,Hangup()
```

`s` is the entry extension Asterisk uses for an FXO/analog call with no dialed digits, which is
how every incoming landline call arrives here — that's the extension that actually matters.

## 4. Greeting audio

`gangsta_greeting.gsm` in this folder is the custom greeting ("Hello! Welcome, you have reached
the Gangsta's Paradise helpline. Please wait for the beep to shoot your query."), generated with
Windows' built-in TTS (`System.Speech.Synthesis`, 8kHz/16-bit/mono) and converted to GSM with
ffmpeg (`ffmpeg -i in.wav -ar 8000 -ac 1 -c:a gsm out.gsm`) to match Asterisk's native sound
format and keep it small enough to move over a slow remote-shell connection.

Install it:
```
sudo cp gangsta_greeting.gsm /var/lib/asterisk/sounds/en/gangsta_greeting.gsm
sudo chown root:root /var/lib/asterisk/sounds/en/gangsta_greeting.gsm
```
Reference it in the dialplan with `Playback(gangsta_greeting)` (no extension). The trailing
beep uses Asterisk's stock `beep.gsm`, already present in `/var/lib/asterisk/sounds/en/`.

No TTS engine (flite/festival/espeak) is installed on the Pi itself; `sox`/`ffmpeg` are
available there for format conversion if you want to generate audio directly on-device instead.

## 5. Let the CLI work without sudo

By default `asterisk -rx` fails for a non-root user ("Unable to connect to remote asterisk") —
the control socket is owned `root:root` mode `0755`. Fix in `/etc/asterisk/asterisk.conf`
(see `asterisk.conf.files-section.after.txt`):

```
[files]
astctlpermissions = 0660
astctlowner = root
astctlgroup = kudo
```

Then **fully cycle the service** (a config reload is not enough — the socket is only created
at startup):

```
sudo systemctl stop asterisk
sudo systemctl start asterisk
```

**Gotcha we actually hit**: `systemctl restart asterisk` can leave the PBX completely down. This
service's LSB init script doesn't reliably kill the old process on stop; systemd sometimes marks
the unit "active (exited)" (exit code 0) even though the daemon never actually restarted, and a
subsequent `systemctl start` then no-ops because systemd already believes it's active. If that
happens: check `ps -C asterisk` and `ls /var/run/asterisk/` — no process and no `asterisk.ctl`
socket means it's actually down despite systemd's status. Force it with an explicit `stop` then
`start` (not `restart`) as separate commands, with a couple seconds between them.

## 6. Apply config-only changes without a restart

`pjsip.conf` / `extensions.conf` edits (endpoints, dialplan) apply live with no dropped calls:

```
sudo asterisk -rx "pjsip reload"
sudo asterisk -rx "dialplan reload"
```

Only the `asterisk.conf` socket-permission change in step 5 needs a full stop/start.

## Verifying everything works

```
asterisk -rx "core show version"          # no sudo needed after step 5
asterisk -rx "pjsip show endpoints"        # should show exactly 1 object: pbx_ata, Avail
asterisk -rx "dialplan show from-ata"      # should show Playback(gangsta_greeting) + beep
                                            # before AGI(agi_voicebot.py), no dead tune context
```
