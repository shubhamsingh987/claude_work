# ESP32 AI voice recorder

Press a button on an ESP32, talk, press it again. The board streams raw
microphone audio to a server on your LAN, which transcribes it, separates the
speakers, and writes the conversation up as notes.

```
INMP441 ──I2S──> ESP32 WROOM-32 ──Wi-Fi, chunked HTTP POST──> server/app.py
                                                                   │
                                          faster-whisper (speech to text)
                                          speaker separation (who said what)
                                          Claude (summary + action items)
                                                                   │
                                                     http://<your-ip>:8000/
```

- `firmware/` – PlatformIO project for the ESP32
- `server/` – FastAPI server, web dashboard, and a hardware-free test client
- [`HARDWARE.md`](HARDWARE.md) – what to buy, with links and prices (~₹1,320)

---

## 1. Wiring

| INMP441 | ESP32 | Note |
|---|---|---|
| VDD | 3V3 | **not** 5V |
| GND | GND | |
| L/R | GND | makes the mic drive the left I2S slot |
| SCK | GPIO32 | bit clock |
| WS  | GPIO25 | word select / LRCL |
| SD  | GPIO33 | data out of the mic |

These defaults match the mic wiring already on the `esp32-espnow-ptt`
walkie-talkie board, so that hardware runs this firmware unmodified. Wiring a
mic from scratch? Any free pins work — change them in `config.h`.

Also: a momentary button from **GPIO4 to GND** (the internal pull-up is
enabled, so no resistor needed), and the on-board LED on GPIO2 is used for
status. All pins are in `firmware/src/config.h`.

LED behaviour: slow blink = joining Wi-Fi · solid = recording · two blinks =
notes came back · three fast blinks = something failed (read the serial log).

---

## 2. Run the server

```bash
cd server
pip install -r requirements.txt
python app.py
```

It prints the URL to open and the exact `SERVER_HOST` line to paste into the
firmware config. On this machine that is:

- Dashboard: **http://192.168.1.14:8000/**
- Ingest endpoint: `http://192.168.1.14:8000/ingest`

The first recording is slow because faster-whisper downloads its model
(~140 MB for `base`); everything after that is warm.

**Windows firewall:** the first run pops a prompt — allow Python on *private*
networks, or the ESP32 cannot reach the server. To add the rule up front:

```bash
netsh advfirewall firewall add rule name="voice-notes 8000" dir=in action=allow protocol=TCP localport=8000
```

## 3. Flash the firmware

Edit `firmware/src/config.h` — Wi-Fi SSID, password, and `SERVER_HOST` — then:

```bash
pio run -t upload -t monitor
```

Run `pio` from PowerShell, not Git Bash.

Press the button, talk, press it again. The serial monitor shows a live RMS
level meter while recording and prints the returned notes when the server is
done. The recording also appears on the dashboard.

---

## Testing without the hardware

`server/tools/simulate_esp32.py` opens the same chunked POST the firmware
does, with the same headers and framing, from any WAV file:

```bash
python tools/simulate_esp32.py meeting.wav
```

You can also drag a `.wav` onto the **upload** button in the dashboard.

---

## Configuration

Everything is environment variables; none are required.

| Variable | Default | Meaning |
|---|---|---|
| `PORT` | `8000` | server port |
| `DATA_DIR` | `server/data` | where sessions are written |
| `WHISPER_MODEL` | `base` | `tiny`/`base`/`small`/`medium`/`large-v3`. `small` is noticeably more accurate and still runs on CPU |
| `WHISPER_DEVICE` | `cpu` | set `cuda` if you have an NVIDIA GPU |
| `WHISPER_COMPUTE` | `int8` | `float16` on GPU |
| `ANTHROPIC_API_KEY` | – | enables Claude-written notes (see below) |
| `SUMMARY_MODEL` | `claude-opus-5` | model used for the notes |
| `HF_TOKEN` | – | enables pyannote speaker separation |

### Notes quality

With `ANTHROPIC_API_KEY` set, notes are written by Claude: summary, key
points, decisions, action items with owners, and open questions. Without it
the server still works but falls back to **extractive** notes — the
highest-scoring sentences pulled straight from the transcript, plus anything
that pattern-matches a commitment. The fallback says so at the top of the
notes, and the engine that ran is shown in the dashboard and returned in the
JSON as `engines.summarizer`.

```powershell
$env:ANTHROPIC_API_KEY = "sk-ant-..."   # then restart app.py
```

### Speaker separation

Three engines, tried best-first. The one that ran is reported as
`engines.diarization`, so the UI never implies more precision than was applied.

| Engine | Setup | Quality |
|---|---|---|
| `pyannote` | `pip install pyannote.audio`, set `HF_TOKEN`, accept the licence for `pyannote/speaker-diarization-3.1` on Hugging Face | best — handles interruptions and finds turn boundaries inside a sentence |
| `ecapa-clustering` | `pip install --index-url https://download.pytorch.org/whl/cpu torch` then `pip install -r requirements-speakers.txt` | good — one voice embedding per transcript segment, clustered. Cannot split a segment two people share |
| `none` | nothing installed | everything is labelled `SPEAKER_00` |

Both real engines assign anonymous labels (`SPEAKER_00`, `SPEAKER_01`). They
tell you *how many distinct voices* there were and *which lines belong to
each*, not who those people are — mapping a label to a name means enrolling a
voice sample per person, which this project does not do.

---

## API

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/ingest` | raw PCM stream from the ESP32; headers `X-Sample-Rate`, `X-Channels`, `X-Bits`, `X-Device-Id`. Responds with the finished transcript and notes |
| `POST` | `/upload` | multipart `.wav` upload, same pipeline |
| `GET` | `/api/sessions` | list all recordings |
| `GET` | `/api/sessions/{id}` | one recording with transcript and notes |
| `GET` | `/api/sessions/{id}/audio.wav` | the audio |
| `DELETE` | `/api/sessions/{id}` | delete a recording |
| `GET` | `/health` | liveness |

Each session is a plain directory under `server/data/sessions/` holding
`audio.wav`, `transcript.json`, `notes.md`, and `meta.json` — readable without
the server running.

---

## Notes on the design

**Why raw PCM instead of compressed audio?** The ESP32-WROOM-32 has no
hardware audio encoder, and 16 kHz mono s16 is only 32 KB/s — comfortable over
Wi-Fi and exactly what Whisper wants, so the server never resamples.

**Why chunked HTTP rather than WebSockets?** The recording has no known length
when it starts. `Transfer-Encoding: chunked` streams an open-ended body with no
extra library on the device, and the response arrives on the same connection,
which is how the board gets its notes back.

**Why does the board hold the connection open while the server thinks?**
So a recording is one round trip with no polling and no device-side state. The
firmware waits up to `RESPONSE_TIMEOUT_MS` (2 minutes); a long recording on a
slow CPU can exceed that, in which case the notes are still saved and visible
on the dashboard — only the serial printout is lost.

**Privacy.** Audio and transcripts are written to disk unencrypted under
`server/data/`, and with `ANTHROPIC_API_KEY` set the transcript text (not the
audio) is sent to the Anthropic API for summarisation. Everything else stays
on your LAN.
