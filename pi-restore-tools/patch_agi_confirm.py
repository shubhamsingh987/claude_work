p = r'C:\Users\singh\claude_work\asterisk-pi\agi_voicebot.py'
s = open(p, newline='').read()

# 1) extra pattern: "switch the llm off", "power the computer down"
s = s.replace('''CMD_ON = re.compile(''', '''CMD_OFF2 = re.compile(r"\\b(turn|switch|power|shut)\\b.{0,25}\\b" + PC_WORDS + r"\\b.{0,15}\\b(off|down)\\b")
YES = re.compile(r"\\b(yes|yeah|yep|yup|confirm|sure|do it|go ahead|please)\\b")
CMD_ON = re.compile(''', 1)
s = s.replace('''    if CMD_OFF.search(t):
        return "off"''', '''    if CMD_OFF.search(t) or CMD_OFF2.search(t):
        return "off"''', 1)

# 2) confirmation step before an actual shutdown
old_start = s.index('        cmd = voice_command(transcript)')
old_end = s.index('        reply_path = os.path.join(RECORD_DIR')
new_block = '''        if pending_off:
            pending_off = False
            if YES.search(transcript.lower()):
                log("Voice command: shutdown confirmed.")
                agi.stream_file("pc_shutdown_ack")
                # detached, so it keeps running (clean shutdown, wait, plug off) after this call ends
                subprocess.Popen([SHUTDOWN_SCRIPT], start_new_session=True, stdin=subprocess.DEVNULL,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return True
            log("Voice command: shutdown cancelled (no yes heard).")
            agi.stream_file("pc_shutdown_cancelled")
            continue

        cmd = voice_command(transcript)
        if cmd == "on":
            agi.stream_file("pc_already_on")
            continue
        if cmd == "off":
            if not (os.path.exists(SHUTDOWN_SCRIPT) and os.path.exists(SHUTDOWN_TOKEN)):
                log("Voice command: shutdown requested but not set up (script/token missing).")
                agi.stream_file("pc_shutdown_unavailable")
                continue
            log("Voice command: shutdown requested, asking for confirmation.")
            agi.stream_file("pc_shutdown_confirm")
            pending_off = True
            continue

'''
s = s[:old_start] + new_block + s[old_end:]

# 3) state variable at the top of run_call
s = s.replace('''    for turn in range(MAX_TURNS):
        record_basename''', '''    pending_off = False   # True while waiting for the caller's yes/no to a shutdown request
    for turn in range(MAX_TURNS):
        record_basename''', 1)

assert 'pending_off = True' in s and 'CMD_OFF2' in s
open(p, 'w', newline='\n').write(s)
print("patched")
