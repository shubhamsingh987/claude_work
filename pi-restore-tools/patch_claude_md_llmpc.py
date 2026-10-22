import shutil
R = r'C:\Users\singh\claude_work'
p = R + r'\CLAUDE.md'
s = open(p, newline='', encoding='utf-8').read().replace('\r\n', '\n')

# 1) voice-shutdown bullet: now live
a = s.index("- **Voice shutdown/menu-2 is NOT live until**")
b = s.index("- **Offline speech:**")
s = s[:a] + '''- **Voice shutdown / menu option 2 is LIVE (2026-10-22)** but the actual power-off was **not** exercised (it would shut the
  user's PC down and cut the plug). Pieces: `POST /shutdown` in the LLM PC's `voice_server.py` (checks `X-Token` against
  `C:\\Users\\home\\pbx_box\\llm_shutdown.token`; no/wrong token = 403, verified), the same token on the Pi in
  `/etc/asterisk/llm_shutdown.token` (generated on the Pi from random bytes, never displayed; copied to the PC through a pipe
  and fingerprint-compared), `shutdown-llm-pc.sh` (clean `shutdown /s /t 15`, waits until the server stops answering, +40 s, then
  plug off; never cuts the plug if the clean shutdown can't be requested) and `shutdown-ready.sh` (token + `GET /shutdown` is
  not 404) which gates the voice command and menu 2 so the bot never pretends. **`shutdown-ready.sh` must run as root** (token is
  mode 600; Asterisk is root) — as `kudo` it reports "not ready".

''' + s[b:]

# 2) new subsection about the LLM PC, placed before the Tuya section
t = s.index("### Tuya plug (replaces the Home Assistant switch for press-1)")
s = s[:t] + '''### The LLM PC (reachable with `ssh llmpc`) — added 2026-10-22
`~/.ssh/config` has `Host llmpc` → `100.86.15.30` (Tailscale), user `home`, key `~/.ssh/id_ed25519_llmpc`; the shell there is
Windows `cmd` (use `powershell -NoProfile -Command ...`, or copy a `.ps1` over with `scp` and run it — quoting through cmd is
painful). The orchestrator is `C:\\Users\\home\\pbx_box\\voice_server.py` (Flask :5000, faster-whisper + Ollama), backup before the
change `voice_server.py.bak.preshutdown`. Claude Code's classifier blocks remote writes until the user explicitly says so in chat.
- **Duplicate server bug (fixed):** two launchers started the same server — the NSSM service **`VoiceBotOrchestrator`**
  (LocalSystem, auto-restarts) and the scheduled task **`VoiceServer`** (logon trigger → `start_server.bat`). Windows lets both bind
  :5000, so requests hit either copy at random (in-memory per-call chat history can be lost between turns). Kept the service,
  **disabled** the task (not deleted). NSSM restarts a killed server within seconds — stop the *service*, not the process.
- **`JellyfinServer` is also an NSSM service** on that PC. A filter on `*nssm*` restarted it by accident during the fix (it came
  back; mention before touching services there). Fix script: `pi-restore-tools/fix_llm_server.ps1` (its NSSM filter is too broad —
  filter on the service name `VoiceBotOrchestrator` before reusing).
- The token file ACL must let `SYSTEM` read it (the service runs as SYSTEM): `icacls ... /grant:r *S-1-5-18:R *S-1-5-32-544:R home:F`.
  A `home`-only ACL made the service answer 503 "not configured".

''' + s[t:]

# 3) open items
s = s.replace("2. Voice shutdown: create `/etc/asterisk/llm_shutdown.token`, add the `/shutdown` route to the Windows orchestrator.\n",
              "2. Voice shutdown is wired and refuses bad tokens, but a real end-to-end shutdown (PC off, then plug off) hasn't been run — do it once on purpose.\n", 1)
open(p, 'w', newline='\n', encoding='utf-8').write(s)

# keep the repo copy of the route identical to what is deployed
snip = open(R + r'\pi-restore-tools\shutdown_route_snippet.py', encoding='utf-8').read()
hdr = '''# DEPLOYED 2026-10-22 in C:\\Users\\home\\pbx_box\\voice_server.py on the LLM PC (just above `if __name__ == "__main__":`).
# Needs C:\\Users\\home\\pbx_box\\llm_shutdown.token = the same secret as /etc/asterisk/llm_shutdown.token on the Pi, readable by
# SYSTEM (the orchestrator runs as the NSSM service VoiceBotOrchestrator). Uses the file's existing `os`, `subprocess`,
# `request`, `jsonify` and `log`.

'''
open(R + r'\asterisk-pi\llm-health-switch\orchestrator-shutdown-route.py', 'w', newline='\n', encoding='utf-8').write(hdr + snip)
print("done")
