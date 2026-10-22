p = r'C:\Users\singh\claude_work\asterisk-pi\agi_pc_voice.py'
s = open(p, newline='').read()

s = s.replace('ON_WORDS = ("turn on", "switch on", "power on", "start", "wake up")',
              'ON_WORDS = ("turn on", "switch on", "power on", "start", "wake up", "yes")', 1)

s = s.replace('''    def stream_file(self, name):
        return self._send(f'STREAM FILE {name} ""')

    def record_file(self, name, secs=5, silence=2):
        return self._send(f'RECORD FILE {name} wav "#" {secs * 1000} BEEP s={silence}')
''', '''    def stream_file(self, name, escape=""):
        return self._send(f'STREAM FILE {name} "{escape}"')

    def record_file(self, name, secs=5, silence=2):
        return self._send(f'RECORD FILE {name} wav "9#" {secs * 1000} BEEP s={silence}')

    def set_variable(self, name, value):
        self._send(f'SET VARIABLE {name} "{value}"')

    @staticmethod
    def pressed_9(result):
        return "result=57" in result
''', 1)

a = s.index("agi = MiniAGI()")
s = s[:a] + '''agi = MiniAGI()
call_id = agi.env.get("agi_uniqueid", f"call_{int(time.time())}")
box = {"ready": threading.Event()}
threading.Thread(target=load_model, args=(box,), daemon=True).start()   # loads while the prompt plays

# Result goes to the dialplan in PCVOICE: ok (switch turned on) | fail | none (not understood) | ivr (caller pressed 9)
outcome = "none"
try:
    r = agi.stream_file("pc_voice_prompt", "9")
    if agi.caller_gone(r):
        sys.exit(0)
    if agi.pressed_9(r):
        outcome = "ivr"
    else:
        wav = f"/tmp/pcvoice_{call_id}"
        r = agi.record_file(wav)
        if agi.caller_gone(r):
            sys.exit(0)
        if agi.pressed_9(r):
            outcome = "ivr"
        else:
            wav += ".wav"
            box["ready"].wait(30)
            if "model" not in box:
                raise RuntimeError(f"speech model failed to load: {box.get('error')}")
            text = transcribe(box, wav) if os.path.exists(wav) else ""
            log(f"heard: {text!r}")
            if any(w in text for w in ON_WORDS):
                rc = subprocess.run([SWITCH_SCRIPT, "on"], timeout=40).returncode
                log(f"switch script exit={rc}")
                outcome = "ok" if rc == 0 else "fail"
except SystemExit:
    raise
except Exception as e:
    log(f"error: {e!r}")
    outcome = "fail"
finally:
    try:
        os.remove(f"/tmp/pcvoice_{call_id}.wav")
    except OSError:
        pass
    try:
        agi.set_variable("PCVOICE", outcome)
    except Exception:
        pass
'''
for needle in ('"yes")', 'outcome = "ivr"', 'PCVOICE'):
    assert needle in s, needle
open(p, 'w', newline='\n').write(s)
print("patched")
