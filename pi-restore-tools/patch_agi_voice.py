import re
p = r'C:\Users\singh\claude_work\asterisk-pi\agi_voicebot.py'
s = open(p, newline='').read()

s = s.replace("import random\nimport threading\n", "import re\nimport random\nimport subprocess\nimport threading\n", 1)

s = s.replace('FILLER_STILL_AFTER = 12   # seconds before saying "still working on it"\n', r'''FILLER_STILL_AFTER = 12   # seconds before saying "still working on it"
SHUTDOWN_SCRIPT = os.environ.get("VOICEBOT_SHUTDOWN_SCRIPT", "/usr/local/bin/shutdown-llm-pc.sh")
SHUTDOWN_TOKEN = os.environ.get("VOICEBOT_SHUTDOWN_TOKEN", "/etc/asterisk/llm_shutdown.token")
# Spoken commands handled on the Pi itself (matched against the transcript the PC returns)
PC_WORDS = r"(pc|computer|llm|server|machine|box)"
CMD_OFF = re.compile(r"\b(turn|switch|power|shut)\b.{0,15}\b(off|down)\b.{0,25}\b" + PC_WORDS + r"\b")
CMD_ON = re.compile(r"\b(turn|switch|power|start)\b.{0,15}\bon\b.{0,25}\b" + PC_WORDS + r"\b")
''', 1)

s = s.replace("def post_turn(wav_path, call_id, box):", '''def voice_command(transcript: str):
    t = transcript.lower()
    if CMD_OFF.search(t):
        return "off"
    if CMD_ON.search(t):
        return "on"
    return None


def post_turn(wav_path, call_id, box):''', 1)

s = s.replace('''        reply_path = os.path.join(RECORD_DIR, f"reply_{call_id}_{turn}.wav")''', '''        cmd = voice_command(transcript)
        if cmd == "on":
            agi.stream_file("pc_already_on")
            continue
        if cmd == "off":
            if not (os.path.exists(SHUTDOWN_SCRIPT) and os.path.exists(SHUTDOWN_TOKEN)):
                log("Voice command: shutdown requested but not set up (script/token missing).")
                agi.stream_file("pc_shutdown_unavailable")
                continue
            log("Voice command: shutting the LLM PC down.")
            agi.stream_file("pc_shutdown_ack")
            # detached, so it keeps running (clean shutdown, wait, plug off) after this call ends
            subprocess.Popen([SHUTDOWN_SCRIPT], start_new_session=True, stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True

        reply_path = os.path.join(RECORD_DIR, f"reply_{call_id}_{turn}.wav")''', 1)

assert 'voice_command(transcript)' in s and 'CMD_OFF = re.compile' in s
open(p, 'w', newline='\n').write(s)
print("patched")
