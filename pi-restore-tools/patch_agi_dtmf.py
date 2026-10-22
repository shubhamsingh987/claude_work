p = r'C:\Users\singh\claude_work\asterisk-pi\agi_voicebot.py'
s = open(p, newline='').read()

# 1) digit helper on MiniAGI
s = s.replace('''    @staticmethod
    def caller_gone(result: str) -> bool:''', '''    @staticmethod
    def digit_of(result: str) -> str:
        """The key the caller pressed, from 'result=NN' (ASCII code), or ''."""
        import re as _re
        m = _re.search(r"result=(\\d+)", result)
        if m and int(m.group(1)) in (35, 42) or (m and 48 <= int(m.group(1)) <= 57):
            return chr(int(m.group(1)))
        return ""

    @staticmethod
    def caller_gone(result: str) -> bool:''', 1)

# 2) wait_with_filler returns a state and listens for 0 / 9
a = s.index("def wait_with_filler(agi, done):")
b = s.index("def run_call():")
s = s[:a] + '''def wait_with_filler(agi, done, first):
    """Spoken filler, then a soft tick, until the reply arrives. Caller keys: 9 = menu, 0 = cancel.
    Returns 'done', 'gone' (hung up), 'ivr' or 'cancel'."""
    start = time.time()
    still_said = False
    r = agi.stream_file("filler_stay" if first else random.choice(FILLER_PHRASES), "09")
    while True:
        if agi.caller_gone(r):
            return "gone"
        d = agi.digit_of(r)
        if d == "9":
            return "ivr"
        if d == "0":
            return "cancel"
        if done.is_set():
            return "done"
        if not still_said and time.time() - start > FILLER_STILL_AFTER:
            still_said = True
            r = agi.stream_file("filler_still", "09")
        else:
            r = agi.stream_file("filler_tick", "09")


''' + s[b:]

# 3) run_call: hint, keys while recording, waiting and replying
s = s.replace('''    pending_off = False   # True while waiting''', '''    asked = 0             # questions sent so far (the first gets the longer "stay on the line" filler)
    r = agi.stream_file("bot_hint", "9")
    if agi.caller_gone(r):
        return True
    if agi.digit_of(r) == "9":
        agi.set_variable("VOICEBOT_NEXT", "ivr")
        return True
    pending_off = False   # True while waiting''', 1)

s = s.replace('''        r = agi.record_file(record_basename, fmt="wav", escape_digits="#",''', '''        r = agi.record_file(record_basename, fmt="wav", escape_digits="09#",''', 1)
s = s.replace('''        if agi.caller_gone(r):
            log("Caller hung up during recording.")
            return True
''', '''        if agi.caller_gone(r):
            log("Caller hung up during recording.")
            return True
        d = agi.digit_of(r)
        if d == "9":
            log("Caller pressed 9 -> menu.")
            agi.set_variable("VOICEBOT_NEXT", "ivr")
            return True
        if d == "0":
            log("Caller pressed 0 while recording -> listening again.")
            continue
''', 1)

s = s.replace('''        if not wait_with_filler(agi, box["done"]):
            log("Caller hung up while waiting for the LLM.")
            return True
        worker.join()
''', '''        state = wait_with_filler(agi, box["done"], asked == 0)
        asked += 1
        if state == "gone":
            log("Caller hung up while waiting for the LLM.")
            return True
        if state == "ivr":
            log("Caller pressed 9 while waiting -> menu.")
            agi.set_variable("VOICEBOT_NEXT", "ivr")
            return True
        if state == "cancel":
            log("Caller pressed 0 -> query cancelled, listening again.")
            continue                      # the worker's late answer is simply ignored
        worker.join()
''', 1)

s = s.replace('''        r = agi.stream_file(reply_path.replace(".wav", ""))
        os.remove(reply_path)
        if agi.caller_gone(r):
            log("Caller hung up during the reply.")
            return True
''', '''        r = agi.stream_file(reply_path.replace(".wav", ""), "09")
        os.remove(reply_path)
        if agi.caller_gone(r):
            log("Caller hung up during the reply.")
            return True
        d = agi.digit_of(r)
        if d == "9":
            log("Caller pressed 9 during the reply -> menu.")
            agi.set_variable("VOICEBOT_NEXT", "ivr")
            return True
''', 1)

for needle in ('state = wait_with_filler', 'filler_stay', 'VOICEBOT_NEXT'):
    assert needle in s, needle
open(p, 'w', newline='\n').write(s)
print("patched")
