#!/usr/bin/env python3
"""
Asterisk AGI script — runs ON THE PI, invoked from the dialplan.
Drives one call: record caller -> POST to orchestrator -> play reply -> repeat.

This version has NO third-party AGI library dependency (pyst2 caused issues
with debug prints polluting stdout, which corrupts the AGI protocol channel).
Instead it implements the tiny bit of the AGI protocol we actually need,
directly, writing ONLY clean AGI commands to stdout.

Install:
    pip3 install requests --break-system-packages
    chmod +x agi_voicebot.py
    Place in /var/lib/asterisk/agi-bin/

Dialplan (extensions.conf) example:
    exten => s,1,Answer()
     same => n,AGI(agi_voicebot.py)
     same => n,Hangup()

Edit ORCHESTRATOR_URL below to point at your Windows box.
"""

import sys
import os
import time
import re
import random
import subprocess
import threading
import requests

# ------------------------------------------------------------------
ORCHESTRATOR_URL = os.environ.get("VOICEBOT_ORCHESTRATOR_URL", "http://192.168.1.31:5000")   # Windows orchestrator box
RECORD_DIR = "/tmp"
MAX_TURNS = 20            # safety cap so a call can't loop forever
SILENCE_TIMEOUT = 3       # seconds of silence that ends a recording
MAX_RECORD_SECS = 15      # max length of a single caller utterance
GOODBYE_WORDS = ("goodbye", "bye", "hang up", "that's all")
LOG_FILE = "/tmp/agi_voicebot.log"   # our own debug log, separate from AGI stdout
FILLER_PHRASES = ("filler_think1", "filler_think2", "filler_think3")  # spoken once while the LLM thinks
FILLER_STILL_AFTER = 12   # seconds before saying "still working on it"
SHUTDOWN_SCRIPT = os.environ.get("VOICEBOT_SHUTDOWN_SCRIPT", "/usr/local/bin/shutdown-llm-pc.sh")
SHUTDOWN_TOKEN = os.environ.get("VOICEBOT_SHUTDOWN_TOKEN", "/etc/asterisk/llm_shutdown.token")
# Spoken commands handled on the Pi itself (matched against the transcript the PC returns)
PC_WORDS = r"(pc|computer|llm|server|machine|box)"
CMD_OFF = re.compile(r"\b(turn|switch|power|shut)\b.{0,15}\b(off|down)\b.{0,25}\b" + PC_WORDS + r"\b")
CMD_OFF2 = re.compile(r"\b(turn|switch|power|shut)\b.{0,25}\b" + PC_WORDS + r"\b.{0,15}\b(off|down)\b")
YES = re.compile(r"\b(yes|yeah|yep|yup|confirm|sure|do it|go ahead|please)\b")
CMD_ON = re.compile(r"\b(turn|switch|power|start)\b.{0,15}\bon\b.{0,25}\b" + PC_WORDS + r"\b")
# ------------------------------------------------------------------


def log(msg: str):
    """Write our own debug output to a file -- NEVER to stdout, which is reserved
    exclusively for the AGI protocol. Mixing the two breaks Asterisk's parser."""
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {msg}\n")
    except Exception:
        pass


class MiniAGI:
    """Minimal AGI protocol client: reads the env header from stdin, sends
    commands to stdout, reads results back from stdin. Nothing else."""

    def __init__(self):
        self.env = {}
        while True:
            line = sys.stdin.readline()
            if not line or line.strip() == "":
                break
            if ":" in line:
                key, _, value = line.partition(":")
                self.env[key.strip()] = value.strip()
        log(f"AGI env received: {self.env}")

    def _send(self, command: str) -> str:
        sys.stdout.write(command + "\n")
        sys.stdout.flush()
        result = sys.stdin.readline().strip()
        log(f"CMD: {command} -> RESULT: {result}")
        return result

    def answer(self):
        self._send("ANSWER")

    def verbose(self, message: str, level: int = 1):
        safe = message.replace('"', "'")
        self._send(f'VERBOSE "{safe}" {level}')

    def record_file(self, filename: str, fmt: str = "wav", escape_digits: str = "#",
                     timeout_ms: int = 15000, silence_secs: int = 3, beep: bool = True):
        beep_flag = "BEEP" if beep else ""
        cmd = f'RECORD FILE {filename} {fmt} "{escape_digits}" {timeout_ms} {beep_flag} s={silence_secs}'
        return self._send(cmd)

    def stream_file(self, filename: str, escape_digits: str = ""):
        cmd = f'STREAM FILE {filename} "{escape_digits}"'
        return self._send(cmd)

    def set_variable(self, name: str, value: str):
        self._send(f'SET VARIABLE {name} "{value}"')

    @staticmethod
    def digit_of(result: str) -> str:
        """The key the caller pressed, from 'result=NN' (ASCII code), or ''."""
        import re as _re
        m = _re.search(r"result=(\d+)", result)
        if m and int(m.group(1)) in (35, 42) or (m and 48 <= int(m.group(1)) <= 57):
            return chr(int(m.group(1)))
        return ""

    @staticmethod
    def caller_gone(result: str) -> bool:
        # STREAM FILE / RECORD FILE report a hung-up caller as result=-1 or (hangup)
        return "result=-1" in result or "(hangup)" in result

    def hangup(self):
        self._send("HANGUP")


# ------------------------------------------------------------------
# Main call flow
# ------------------------------------------------------------------
def shutdown_ready() -> bool:
    """True only if a clean shutdown can really happen (script + token on the Pi, /shutdown route on the PC)."""
    if not (os.path.exists(SHUTDOWN_SCRIPT) and os.path.exists(SHUTDOWN_TOKEN)):
        return False
    try:
        return requests.get(f"{ORCHESTRATOR_URL}/shutdown", timeout=4).status_code != 404
    except requests.RequestException:
        return False


def voice_command(transcript: str):
    t = transcript.lower()
    if CMD_OFF.search(t) or CMD_OFF2.search(t):
        return "off"
    if CMD_ON.search(t):
        return "on"
    return None


def post_turn(wav_path, call_id, box):
    """Runs in a worker thread so the main thread can keep audio playing."""
    try:
        with open(wav_path, "rb") as f:
            box["resp"] = requests.post(
                f"{ORCHESTRATOR_URL}/process_turn",
                data={"call_id": call_id},
                files={"audio": f},
                timeout=60,
            )
    except Exception as e:  # network error, timeout, ...
        box["error"] = e
    finally:
        if os.path.exists(wav_path):
            os.remove(wav_path)
        box["done"].set()


def wait_with_filler(agi, done, first):
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


def run_call():
    """Returns True on a clean end (goodbye / turn cap / caller hung up),
    False if something broke -- the dialplan then tells the caller to call again."""
    call_id = agi.env.get("agi_uniqueid", f"call_{int(time.time())}")
    log(f"Voicebot starting for call_id={call_id}")
    agi.verbose(f"Voicebot starting for call_id={call_id}")

    asked = 0             # questions sent so far (the first gets the longer "stay on the line" filler)
    r = agi.stream_file("bot_hint", "9")
    if agi.caller_gone(r):
        return True
    if agi.digit_of(r) == "9":
        agi.set_variable("VOICEBOT_NEXT", "ivr")
        return True
    pending_off = False   # True while waiting for the caller's yes/no to a shutdown request
    for turn in range(MAX_TURNS):
        record_basename = os.path.join(RECORD_DIR, f"rec_{call_id}_{turn}")
        r = agi.record_file(record_basename, fmt="wav", escape_digits="09#",
                            timeout_ms=MAX_RECORD_SECS * 1000,
                            silence_secs=SILENCE_TIMEOUT, beep=True)
        if agi.caller_gone(r):
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
        wav_path = record_basename + ".wav"

        if not os.path.exists(wav_path) or os.path.getsize(wav_path) < 100:
            log("No audio captured, reprompting.")
            agi.verbose("No audio captured, reprompting.")
            continue

        box = {"done": threading.Event()}
        worker = threading.Thread(target=post_turn, args=(wav_path, call_id, box), daemon=True)
        worker.start()
        state = wait_with_filler(agi, box["done"], asked == 0)
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

        if "error" in box:
            log(f"Orchestrator request failed: {box['error']}")
            agi.verbose(f"Orchestrator request failed: {box['error']}")
            return False
        resp = box["resp"]

        if resp.status_code == 204:
            log("Empty transcript, reprompting.")
            agi.verbose("Empty transcript, reprompting.")
            continue

        if resp.status_code != 200:
            log(f"Orchestrator error {resp.status_code}: {resp.text}")
            agi.verbose(f"Orchestrator error {resp.status_code}")
            return False

        transcript = resp.headers.get("X-Transcript", "")
        reply_text = resp.headers.get("X-Reply", "")
        log(f"Caller said: {transcript!r} | Bot replied: {reply_text!r}")
        agi.verbose(f"Caller said: {transcript!r} | Bot replied: {reply_text!r}")

        if pending_off:
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
            if not shutdown_ready():
                log("Voice command: shutdown requested but not set up (script/token missing).")
                agi.stream_file("pc_shutdown_unavailable")
                continue
            log("Voice command: shutdown requested, asking for confirmation.")
            agi.stream_file("pc_shutdown_confirm")
            pending_off = True
            continue

        reply_path = os.path.join(RECORD_DIR, f"reply_{call_id}_{turn}.wav")
        with open(reply_path, "wb") as f:
            f.write(resp.content)
        r = agi.stream_file(reply_path.replace(".wav", ""), "09")
        os.remove(reply_path)
        if agi.caller_gone(r):
            log("Caller hung up during the reply.")
            return True
        d = agi.digit_of(r)
        if d == "9":
            log("Caller pressed 9 during the reply -> menu.")
            agi.set_variable("VOICEBOT_NEXT", "ivr")
            return True

        if any(word in transcript.lower() for word in GOODBYE_WORDS):
            log("Caller said goodbye, ending call.")
            agi.verbose("Caller said goodbye, ending call.")
            return True
    return True


agi = MiniAGI()
agi.answer()
try:
    ok = run_call()
except Exception as e:  # any bug or surprise: report it instead of dropping the call
    log(f"Unhandled error: {e!r}")
    ok = False

try:
    call_id = agi.env.get("agi_uniqueid", "")
    requests.post(f"{ORCHESTRATOR_URL}/end_call", data={"call_id": call_id}, timeout=5)
except requests.RequestException:
    pass

# The dialplan checks this: anything but 1 -> "sorry, an issue occurred, please call again".
agi.set_variable("VOICEBOT_OK", "1" if ok else "0")
