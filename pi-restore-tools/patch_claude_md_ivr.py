p = r'C:\Users\singh\claude_work\CLAUDE.md'
s = open(p, newline='', encoding='utf-8').read().replace('\r\n', '\n')
a = s.index("### Phone menu now (live;")
b = s.index("### Tuya plug (replaces the Home Assistant switch for press-1)")
new = '''### Phone menu / IVR (live; source `asterisk-pi/extensions.conf.custom-section.2026-10-22-ivr.txt`)
One entry point (`from-ata` `s`; `pbx_ata` just jumps to it) and **one main menu reachable from everywhere**:
- **Call start:** greeting → `check-llm-health.sh` → PC up: assistant (`agi_voicebot.py`); PC off: the agent *asks* "The AI PC
  is off. Press 1, or say yes, to turn it on, or 9 for the menu". 1 = plug on; silence = `agi_pc_voice.py` (Vosk) listens for
  "yes / turn on". After switching on, the caller **stays on the line** (tick sound, poll health every ~8 s, up to ~25 tries) and
  is **connected to the assistant automatically** when the PC answers; 9 leaves for the menu; timeout → menu.
- **With the assistant:** `bot_hint` ("press 9 any time for the menu, 0 to cancel a question"). While the PC thinks: first
  question gets `filler_stay` ("stay on the line… 0 cancel, 9 menu"), later ones a short filler, then soft ticks, "still working"
  after 12 s. **9** (during recording, thinking or the reply) = main menu; **0** while thinking = cancel that question and
  listen again (the PC's late answer is ignored). **Any failure** (Ollama/server crash, HTTP error, timeout, script bug) →
  `voicebot_error` ("sorry, an issue occurred") **then the main menu — never a silent hang-up**. Caller hang-ups are detected.
- **Main menu (`ivr_menu`):** 1 PC on, 2 PC off (asks "press 1 to confirm"; needs the shutdown token, else says not set up),
  3 ring the phone (`Dial(PJSIP/pbx_ata,30,r)` — tested, it rang), 4 talk to the assistant (if the PC is off → the turn-on
  question), 5 hang up. Idle/invalid input repeats the menu up to 3 times, then says goodbye.
- **Voice commands in a live conversation** (`agi_voicebot.py`, matched on the PC's `X-Transcript`): "turn off / shut down the
  pc/computer/llm/server" → "say yes to confirm" → only then `shutdown-llm-pc.sh` (detached); "turn on the pc" → "already on".
- **Voice shutdown/menu-2 is NOT live until** `/etc/asterisk/llm_shutdown.token` exists on the Pi (user creates) and the
  `/shutdown` route from `asterisk-pi/llm-health-switch/orchestrator-shutdown-route.py` is added to the Windows orchestrator.
  Until then it says shutdown "is not set up" and never cuts power (`shutdown-llm-pc.sh` cuts the plug only after the PC stops
  answering; a hard cut on a running Windows PC can corrupt files).
- **Offline speech:** Vosk + `vosk-model-small-en-us-0.15` in `/opt/vosk`. The model wants **16 kHz**, Asterisk records 8 kHz →
  upsampled in the script (Python 3.13 has no `audioop`). Grammar-restricted (yes / turn on / switch on / power on / start /
  wake up). Tested only with clean TTS clips (0.5 s, model load 4 s in the background) — **not yet on a real phone line.**
- **Tested:** every AGI path against a mock server/fake AGI (9/0 at each phase, errors, cancel, shutdown confirm/cancel/not-set-up,
  voice on/other/9). **The dialplan flow itself (Read/Goto labels, the wait loop, menu) has only been load-checked, not run
  end-to-end on a real call.**
- **Deploy gotchas (cost an outage of calls for ~2 min on 2026-10-22):** when splicing a custom block into `extensions.conf`,
  find the `[from-ht813]` header with an *anchored* match (`^\\[from-ht813\\]$`) — the first plain mention of the name is inside a
  comment, and a half-comment line makes Asterisk reject the whole file (`There is no existence of 'from-ata' context`). Always
  `dialplan show from-ata` after a reload and roll back from `extensions.conf.bak.*` if it's gone. Build scripts live in
  `pi-restore-tools/` (`build_ivr_dialplan.py`, `patch_*.py`).

'''
s = s[:a] + new + s[b:]
s = s.replace("3. End-to-end test calls: filler + error message, press 1/3, the offline \"say turn on\" on a real line.",
              "3. End-to-end test calls: IVR (9/0 keys), filler + error→menu, PC-off \"yes → boots → auto-connect\", press 1/3, voice yes on a real line.")
open(p, 'w', newline='\n', encoding='utf-8').write(s)
print("CLAUDE.md updated:", len(s.splitlines()), "lines")
