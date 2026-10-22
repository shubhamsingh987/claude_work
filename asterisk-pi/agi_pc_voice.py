#!/opt/vosk/venv/bin/python3
"""
Asterisk AGI script — runs ON THE PI when the LLM PC is offline and the caller neither pressed
a key nor hung up. Listens (offline, with Vosk) for "turn on" and then switches the PC's plug on.

Flow: play prompt -> beep + record a few seconds -> Vosk (restricted grammar) -> if the caller
said "turn on" run /usr/local/bin/turn-on-tuya.sh on -> speak the result -> return (dialplan hangs up).

Like agi_voicebot.py this speaks ONLY AGI protocol on stdout; debug output goes to a log file.
"""
import json
import os
import subprocess
import sys
import threading
import time
import wave

MODEL_DIR = "/opt/vosk/model"
SWITCH_SCRIPT = os.environ.get("PC_VOICE_SWITCH_SCRIPT", "/usr/local/bin/turn-on-tuya.sh")
LOG_FILE = "/tmp/agi_pc_voice.log"
# Restricted vocabulary: far more accurate on a small model than free dictation.
GRAMMAR = ["turn on", "switch on", "power on", "start", "wake up", "on", "yes", "no", "cancel", "[unk]"]
ON_WORDS = ("turn on", "switch on", "power on", "start", "wake up", "yes")


def log(msg):
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {msg}\n")
    except Exception:
        pass


class MiniAGI:
    def __init__(self):
        self.env = {}
        while True:
            line = sys.stdin.readline()
            if not line or line.strip() == "":
                break
            if ":" in line:
                k, _, v = line.partition(":")
                self.env[k.strip()] = v.strip()

    def _send(self, command):
        sys.stdout.write(command + "\n")
        sys.stdout.flush()
        result = sys.stdin.readline().strip()
        log(f"CMD: {command} -> {result}")
        return result

    def stream_file(self, name, escape=""):
        return self._send(f'STREAM FILE {name} "{escape}"')

    def record_file(self, name, secs=5, silence=2):
        return self._send(f'RECORD FILE {name} wav "9#" {secs * 1000} BEEP s={silence}')

    def set_variable(self, name, value):
        self._send(f'SET VARIABLE {name} "{value}"')

    @staticmethod
    def pressed_9(result):
        return "result=57" in result

    @staticmethod
    def caller_gone(result):
        return "result=-1" in result or "(hangup)" in result


def upsample_2x(pcm: bytes) -> bytes:
    """8 kHz -> 16 kHz (linear interpolation). Asterisk records 8 kHz; the Vosk model wants 16 kHz.
    (audioop is gone in Python 3.13, so do it with array.)"""
    from array import array
    a = array("h")
    a.frombytes(pcm[: len(pcm) - (len(pcm) % 2)])
    out = array("h", bytes(len(a) * 4))
    for i, v in enumerate(a):
        nxt = a[i + 1] if i + 1 < len(a) else v
        out[2 * i] = v
        out[2 * i + 1] = (v + nxt) // 2
    return out.tobytes()


def transcribe(model_box, wav_path):
    from vosk import KaldiRecognizer
    with wave.open(wav_path, "rb") as w:
        rate = w.getframerate()
        pcm = w.readframes(w.getnframes())
    if rate == 8000:
        pcm, rate = upsample_2x(pcm), 16000
    rec = KaldiRecognizer(model_box["model"], rate, json.dumps(GRAMMAR))
    for i in range(0, len(pcm), 8000):
        rec.AcceptWaveform(pcm[i:i + 8000])
    return json.loads(rec.FinalResult()).get("text", "")


def load_model(box):
    try:
        from vosk import Model, SetLogLevel
        SetLogLevel(-1)
        box["model"] = Model(MODEL_DIR)
    except Exception as e:
        box["error"] = e
    finally:
        box["ready"].set()


agi = MiniAGI()
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
