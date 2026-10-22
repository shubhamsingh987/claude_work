import os
R = r'C:\Users\singh\claude_work\asterisk-pi'

# 1) shutdown-ready.sh: exit 0 only if shutdown can really work (token present AND the PC's /shutdown route exists)
open(os.path.join(R, 'llm-health-switch', 'shutdown-ready.sh'), 'w', newline='\n').write('''#!/bin/bash
# Exit 0 only if a clean remote shutdown can actually work: the token file exists on the Pi AND the
# LLM PC's orchestrator has a /shutdown route (a GET to a POST-only Flask route answers 405; 404 = not there).
URL="${LLM_URL:-http://192.168.1.31:5000}"
[ -r /etc/asterisk/llm_shutdown.token ] || exit 1
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "$URL/shutdown")
case "$CODE" in 000|404) exit 1;; *) exit 0;; esac
''')

# 2) AGI: use a real readiness check instead of "files exist"
p = os.path.join(R, 'agi_voicebot.py')
s = open(p, newline='').read()
s = s.replace('''def voice_command(transcript: str):''', '''def shutdown_ready() -> bool:
    """True only if a clean shutdown can really happen (script + token on the Pi, /shutdown route on the PC)."""
    if not (os.path.exists(SHUTDOWN_SCRIPT) and os.path.exists(SHUTDOWN_TOKEN)):
        return False
    try:
        return requests.get(f"{ORCHESTRATOR_URL}/shutdown", timeout=4).status_code != 404
    except requests.RequestException:
        return False


def voice_command(transcript: str):''', 1)
old = "            if not (os.path.exists(SHUTDOWN_SCRIPT) and os.path.exists(SHUTDOWN_TOKEN)):"
assert old in s
s = s.replace(old, "            if not shutdown_ready():", 1)
open(p, 'w', newline='\n').write(s)

# 3) dialplan: same check in menu option 2
p = os.path.join(R, 'extensions.conf.custom-section.2026-10-22-ivr.txt')
d = open(p, newline='').read()
old = ' same => n,System(test -r /etc/asterisk/llm_shutdown.token)'
assert old in d
d = d.replace(old, ' same => n,System(/usr/local/bin/shutdown-ready.sh)', 1)
open(p, 'w', newline='\n').write(d)

# keep the generator in sync so a rebuild does not undo it
p = r'C:\Users\singh\claude_work\pi-restore-tools\build_ivr_dialplan.py'
g = open(p, newline='').read()
assert 'System(test -r /etc/asterisk/llm_shutdown.token)' in g
g = g.replace('System(test -r /etc/asterisk/llm_shutdown.token)', 'System(/usr/local/bin/shutdown-ready.sh)', 1)
open(p, 'w', newline='\n').write(g)
print("patched")
