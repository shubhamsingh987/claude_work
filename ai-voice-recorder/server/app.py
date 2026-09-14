"""Local server for the ESP32 voice recorder.

  POST /ingest   raw PCM streamed from the ESP32 (chunked); on stream close it
                 transcribes, separates speakers, summarises, and returns JSON.
  POST /upload   same pipeline for a .wav you upload by hand - lets you test
                 the whole server without any hardware attached.
  GET  /         browsable list of every session with transcript and notes.

Run it with:  python app.py        (or: uvicorn app:app --host 0.0.0.0 --port 8000)
"""

from __future__ import annotations

import json
import logging
import os
import shutil
import socket
import time
import uuid
import wave
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request, UploadFile, File
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse
from starlette.concurrency import run_in_threadpool

import pipeline

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-7s %(name)s | %(message)s",
    datefmt="%H:%M:%S",
)
for noisy in ("speechbrain", "urllib3", "huggingface_hub", "pydot", "filelock"):
    logging.getLogger(noisy).setLevel(logging.WARNING)
log = logging.getLogger("server")

BASE_DIR = Path(__file__).parent
DATA_DIR = Path(os.environ.get("DATA_DIR", BASE_DIR / "data"))
SESSIONS_DIR = DATA_DIR / "sessions"
SESSIONS_DIR.mkdir(parents=True, exist_ok=True)

PORT = int(os.environ.get("PORT", "8000"))
MAX_UPLOAD_BYTES = int(os.environ.get("MAX_UPLOAD_BYTES", 200 * 1024 * 1024))

app = FastAPI(title="ESP32 voice notes")


# ---------------------------------------------------------------------------
# Session storage
# ---------------------------------------------------------------------------
def new_session_id() -> str:
    return time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:4]


def session_dir(sid: str) -> Path:
    # `sid` reaches us from the URL: keep it to the shape new_session_id makes
    # so nothing can walk out of the sessions directory.
    if not sid.replace("-", "").isalnum():
        raise HTTPException(400, "bad session id")
    return SESSIONS_DIR / sid


def write_wav(pcm_path: Path, wav_path: Path, sample_rate: int,
              channels: int, bits: int) -> None:
    with wave.open(str(wav_path), "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(bits // 8)
        w.setframerate(sample_rate)
        with open(pcm_path, "rb") as raw:
            while block := raw.read(1 << 20):
                w.writeframes(block)


def save_session(sid: str, meta: dict, result: pipeline.Result | None) -> None:
    d = session_dir(sid)
    (d / "meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    if result is not None:
        (d / "transcript.json").write_text(
            json.dumps(result.to_dict(), indent=2, ensure_ascii=False),
            encoding="utf-8")
        (d / "notes.md").write_text(result.notes, encoding="utf-8")


def load_session(sid: str) -> dict:
    d = session_dir(sid)
    if not (d / "meta.json").exists():
        raise HTTPException(404, "no such session")
    out = json.loads((d / "meta.json").read_text(encoding="utf-8"))
    tpath = d / "transcript.json"
    if tpath.exists():
        out.update(json.loads(tpath.read_text(encoding="utf-8")))
    out["id"] = sid
    return out


# ---------------------------------------------------------------------------
# Processing
# ---------------------------------------------------------------------------
def run_pipeline(sid: str, wav_path: Path, meta: dict) -> dict:
    """Blocking; always called off the event loop."""
    try:
        result = pipeline.process(str(wav_path))
    except Exception as exc:                           # noqa: BLE001
        log.exception("pipeline failed for %s", sid)
        meta["status"] = "error"
        meta["error"] = f"{type(exc).__name__}: {exc}"
        save_session(sid, meta, None)
        return {"session": sid, "status": "error", "error": meta["error"]}

    meta["status"] = "done"
    meta["duration_sec"] = result.duration
    meta["speakers"] = result.speakers
    meta["engines"] = result.meta
    save_session(sid, meta, result)

    log.info("session %s done: %.1fs, %d speakers, %d utterances",
             sid, result.duration, len(result.speakers), len(result.utterances))
    return {
        "session": sid,
        "status": "ok",
        "url": f"/s/{sid}",
        "duration_sec": result.duration,
        "language": result.language,
        "speakers": result.speakers,
        "engines": result.meta,
        "transcript": [
            {"t": u.start, "speaker": u.speaker, "text": u.text}
            for u in result.utterances
        ],
        "notes": result.notes,
    }


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------
@app.get("/health")
async def health():
    return {"ok": True, "sessions": len(list(SESSIONS_DIR.glob("*/meta.json")))}


@app.post("/ingest")
async def ingest(request: Request):
    """Raw PCM streamed from the ESP32. Format comes from the X- headers."""
    h = request.headers
    sample_rate = int(h.get("x-sample-rate", 16000))
    channels = int(h.get("x-channels", 1))
    bits = int(h.get("x-bits", 16))
    device = h.get("x-device-id", "unknown")

    if bits not in (16, 32) or channels not in (1, 2):
        raise HTTPException(400, "unsupported X-Bits / X-Channels")

    sid = new_session_id()
    d = session_dir(sid)
    d.mkdir(parents=True, exist_ok=True)
    pcm_path, wav_path = d / "audio.pcm", d / "audio.wav"

    log.info("session %s: %s streaming %d Hz / %d ch / %d bit",
             sid, device, sample_rate, channels, bits)

    received = 0
    started = time.time()
    with open(pcm_path, "wb") as f:
        async for chunk in request.stream():
            if not chunk:
                continue
            received += len(chunk)
            if received > MAX_UPLOAD_BYTES:
                log.warning("session %s exceeded MAX_UPLOAD_BYTES, truncating", sid)
                break
            f.write(chunk)

    if received == 0:
        shutil.rmtree(d, ignore_errors=True)
        raise HTTPException(400, "empty audio stream")

    write_wav(pcm_path, wav_path, sample_rate, channels, bits)
    pcm_path.unlink(missing_ok=True)

    meta = {
        "id": sid,
        "device": device,
        "created": time.strftime("%Y-%m-%d %H:%M:%S"),
        "sample_rate": sample_rate,
        "channels": channels,
        "bits": bits,
        "bytes": received,
        "stream_sec": round(time.time() - started, 1),
        "status": "processing",
    }
    save_session(sid, meta, None)
    log.info("session %s: %.1f KB received, processing...", sid, received / 1024)

    return JSONResponse(await run_in_threadpool(run_pipeline, sid, wav_path, meta))


@app.post("/upload")
async def upload(file: UploadFile = File(...)):
    """Same pipeline, for a .wav uploaded from the browser or curl."""
    sid = new_session_id()
    d = session_dir(sid)
    d.mkdir(parents=True, exist_ok=True)
    wav_path = d / "audio.wav"

    with open(wav_path, "wb") as f:
        shutil.copyfileobj(file.file, f)

    try:
        with wave.open(str(wav_path), "rb") as w:
            sample_rate, channels, bits = w.getframerate(), w.getnchannels(), w.getsampwidth() * 8
    except wave.Error as exc:
        shutil.rmtree(d, ignore_errors=True)
        raise HTTPException(400, f"not a readable WAV file: {exc}") from exc

    meta = {
        "id": sid,
        "device": f"upload:{file.filename}",
        "created": time.strftime("%Y-%m-%d %H:%M:%S"),
        "sample_rate": sample_rate,
        "channels": channels,
        "bits": bits,
        "bytes": wav_path.stat().st_size,
        "status": "processing",
    }
    save_session(sid, meta, None)
    return JSONResponse(await run_in_threadpool(run_pipeline, sid, wav_path, meta))


@app.get("/api/sessions")
async def list_sessions():
    out = []
    for meta_file in SESSIONS_DIR.glob("*/meta.json"):
        try:
            m = json.loads(meta_file.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        m["id"] = meta_file.parent.name
        m["has_notes"] = (meta_file.parent / "notes.md").exists()
        out.append(m)
    out.sort(key=lambda m: m["id"], reverse=True)
    return out


@app.get("/api/sessions/{sid}")
async def get_session(sid: str):
    return load_session(sid)


@app.delete("/api/sessions/{sid}")
async def delete_session(sid: str):
    d = session_dir(sid)
    if not d.exists():
        raise HTTPException(404, "no such session")
    shutil.rmtree(d, ignore_errors=True)
    return {"deleted": sid}


@app.get("/api/sessions/{sid}/audio.wav")
async def get_audio(sid: str):
    path = session_dir(sid) / "audio.wav"
    if not path.exists():
        raise HTTPException(404, "no audio for this session")
    return FileResponse(path, media_type="audio/wav")


@app.get("/s/{sid}", response_class=HTMLResponse)
async def session_page(sid: str):
    load_session(sid)                      # 404s early if the id is unknown
    return HTMLResponse(INDEX_HTML)


@app.get("/", response_class=HTMLResponse)
async def index():
    return HTMLResponse(INDEX_HTML)


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------
INDEX_HTML = r"""<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Voice notes</title>
<style>
  :root{--bg:#f7f7f8;--panel:#fff;--ink:#1a1a1c;--muted:#6b6b73;--line:#e3e3e7;
        --accent:#4f46e5;--code:#f2f2f5}
  @media (prefers-color-scheme:dark){:root{--bg:#131316;--panel:#1c1c20;--ink:#ececed;
        --muted:#9a9aa4;--line:#2e2e35;--accent:#8b85f5;--code:#252529}}
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.55 system-ui,
       -apple-system,Segoe UI,Roboto,sans-serif}
  .wrap{max-width:1180px;margin:0 auto;padding:24px 20px 60px}
  header{display:flex;align-items:baseline;gap:14px;flex-wrap:wrap;margin-bottom:20px}
  h1{font-size:20px;margin:0;letter-spacing:-.01em}
  .sub{color:var(--muted);font-size:13px}
  .grid{display:grid;grid-template-columns:300px 1fr;gap:20px;align-items:start}
  @media(max-width:820px){.grid{grid-template-columns:1fr}}
  .card{background:var(--panel);border:1px solid var(--line);border-radius:12px}
  .list{overflow:hidden}
  .item{padding:11px 14px;border-bottom:1px solid var(--line);cursor:pointer}
  .item:last-child{border-bottom:0}
  .item:hover{background:var(--code)}
  .item.on{background:var(--code);box-shadow:inset 3px 0 0 var(--accent)}
  .item b{display:block;font-weight:600;font-size:13.5px}
  .item span{color:var(--muted);font-size:12px}
  .pane{padding:20px 22px;min-height:320px}
  .empty{color:var(--muted);padding:40px 22px;text-align:center}
  .tags{display:flex;gap:6px;flex-wrap:wrap;margin:2px 0 16px}
  .tag{font-size:11.5px;color:var(--muted);background:var(--code);
       border:1px solid var(--line);border-radius:999px;padding:2px 9px}
  audio{width:100%;margin-bottom:18px}
  .tabs{display:flex;gap:4px;border-bottom:1px solid var(--line);margin-bottom:16px}
  .tab{padding:7px 13px;border:0;background:none;color:var(--muted);cursor:pointer;
       font:inherit;font-size:13.5px;border-bottom:2px solid transparent;margin-bottom:-1px}
  .tab.on{color:var(--ink);border-bottom-color:var(--accent);font-weight:600}
  .utt{display:grid;grid-template-columns:58px 108px 1fr;gap:10px;padding:5px 0;
       border-bottom:1px solid var(--line);font-size:14px}
  .utt:last-child{border-bottom:0}
  .t{color:var(--muted);font-variant-numeric:tabular-nums;font-size:12.5px;padding-top:2px}
  .spk{font-weight:600;font-size:12.5px;padding-top:2px;overflow:hidden;text-overflow:ellipsis}
  .notes h2{font-size:15px;margin:20px 0 7px;letter-spacing:-.01em}
  .notes h2:first-child{margin-top:0}
  .notes ul{margin:6px 0;padding-left:20px}
  .notes li{margin:3px 0}
  .notes blockquote{margin:0 0 14px;padding:9px 13px;background:var(--code);
       border-left:3px solid var(--accent);border-radius:0 7px 7px 0;
       color:var(--muted);font-size:13px}
  code{background:var(--code);padding:1px 5px;border-radius:4px;font-size:13px}
  .btn{border:1px solid var(--line);background:var(--panel);color:var(--muted);
       border-radius:7px;padding:5px 11px;font:inherit;font-size:12.5px;cursor:pointer}
  .btn:hover{color:var(--ink)}
  .row{display:flex;justify-content:space-between;align-items:center;gap:12px;margin-bottom:12px}
</style></head><body><div class="wrap">
<header>
  <h1>Voice notes</h1>
  <span class="sub" id="sub">loading…</span>
  <span style="flex:1"></span>
  <label class="btn" style="cursor:pointer">upload .wav
    <input type="file" id="up" accept=".wav,audio/wav" hidden></label>
</header>
<div class="grid">
  <div class="card list" id="list"></div>
  <div class="card"><div class="pane" id="pane">
    <div class="empty">Select a recording, or press the button on the ESP32.</div>
  </div></div>
</div></div>
<script>
const $ = s => document.querySelector(s);
let sessions = [], current = null, tab = "notes";

const esc = s => s.replace(/[&<>]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;"}[c]));
const clock = s => Math.floor(s/60) + ":" + String(Math.floor(s%60)).padStart(2,"0");

// Speaker colours: spaced around the wheel by position in the speaker list,
// so SPEAKER_00 and SPEAKER_01 are obviously different at a glance.
let hueOf = () => 210;
function makePalette(speakers) {
  const map = {};
  (speakers || []).forEach((s, i) => { map[s] = (210 + i * 137.5) % 360; });
  hueOf = s => map[s] ?? 210;
}

let listSig = null;

async function loadList(select) {
  sessions = await (await fetch("/api/sessions")).json();
  $("#sub").textContent = sessions.length
    ? sessions.length + " recording" + (sessions.length===1?"":"s")
    : "no recordings yet";

  // Only touch the DOM when something actually changed - the background poll
  // must not tear elements out from under a click.
  const sig = JSON.stringify(sessions.map(s => [s.id, s.status, s.speakers?.length]))
            + "|" + current;
  if (sig === listSig && !select) return;
  listSig = sig;

  $("#list").innerHTML = sessions.map(s => `
    <div class="item ${current===s.id?"on":""}" data-id="${s.id}">
      <b>${esc(s.created || s.id)}</b>
      <span>${esc(s.device||"")} · ${s.duration_sec ? clock(s.duration_sec) : s.status}
      ${s.speakers?.length ? " · " + s.speakers.length + " speaker" + (s.speakers.length===1?"":"s") : ""}</span>
    </div>`).join("") || `<div class="empty">nothing yet</div>`;
  document.querySelectorAll(".item").forEach(el =>
    el.onclick = () => open(el.dataset.id));
  if (select) open(select);
}

async function open(id) {
  current = id;
  document.querySelectorAll(".item").forEach(el =>
    el.classList.toggle("on", el.dataset.id === id));
  const s = await (await fetch("/api/sessions/" + id)).json();
  render(s);
}

function render(s) {
  const e = s.engines || {};
  makePalette(s.speakers);
  const tags = [
    s.created, s.device,
    s.duration_sec ? clock(s.duration_sec) : null,
    s.language ? "lang: " + s.language : null,
    e.asr, e.diarization ? "speakers: " + e.diarization : null,
    e.summarizer ? "notes: " + e.summarizer : null,
  ].filter(Boolean);

  $("#pane").innerHTML = `
    <div class="row">
      <div class="tags">${tags.map(t=>`<span class="tag">${esc(String(t))}</span>`).join("")}</div>
      <button class="btn" id="del">delete</button>
    </div>
    <audio controls src="/api/sessions/${s.id}/audio.wav"></audio>
    ${s.error ? `<blockquote>${esc(s.error)}</blockquote>` : ""}
    <div class="tabs">
      <button class="tab ${tab==="notes"?"on":""}" data-t="notes">Notes</button>
      <button class="tab ${tab==="transcript"?"on":""}" data-t="transcript">Transcript</button>
    </div>
    <div id="body"></div>`;

  $("#del").onclick = async () => {
    if (!confirm("Delete this recording?")) return;
    await fetch("/api/sessions/" + s.id, {method:"DELETE"});
    current = null;
    $("#pane").innerHTML = `<div class="empty">Deleted.</div>`;
    loadList();
  };
  document.querySelectorAll(".tab").forEach(b =>
    b.onclick = () => { tab = b.dataset.t; render(s); });

  $("#body").innerHTML = tab === "notes"
    ? `<div class="notes">${md(s.notes || "_no notes_")}</div>`
    : (s.utterances || []).map(u => `
        <div class="utt">
          <div class="t">${clock(u.start)}</div>
          <div class="spk" style="color:hsl(${hueOf(u.speaker)} 65% 52%)">${esc(u.speaker)}</div>
          <div>${esc(u.text)}</div>
        </div>`).join("") || `<div class="empty">no speech detected</div>`;
}

// Just enough markdown for what the summariser emits.
function md(t) {
  const lines = esc(t).split("\n");
  let out = "", list = null;
  const closeList = () => { if (list) { out += `</${list}>`; list = null; } };
  for (let ln of lines) {
    ln = ln.replace(/`([^`]+)`/g, "<code>$1</code>")
           .replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
           .replace(/^\s*- \[ \] /, "☐ ")
           .replace(/^\s*- \[x\] /i, "☑ ");
    if (/^#{1,3} /.test(ln))      { closeList(); out += `<h2>${ln.replace(/^#+ /,"")}</h2>`; }
    else if (/^&gt; /.test(ln))   { closeList(); out += `<blockquote>${ln.slice(5)}</blockquote>`; }
    else if (/^\s*[-*] /.test(ln)){ if (list!=="ul") { closeList(); out += "<ul>"; list="ul"; }
                                    out += `<li>${ln.replace(/^\s*[-*] /,"")}</li>`; }
    else if (/^\s*\d+\. /.test(ln)){ if (list!=="ol") { closeList(); out += "<ol>"; list="ol"; }
                                    out += `<li>${ln.replace(/^\s*\d+\. /,"")}</li>`; }
    else if (ln.trim() === "")    { closeList(); }
    else                          { closeList(); out += `<p>${ln}</p>`; }
  }
  closeList();
  return out;
}

$("#up").onchange = async ev => {
  const f = ev.target.files[0];
  if (!f) return;
  $("#sub").textContent = "processing " + f.name + " …";
  const fd = new FormData(); fd.append("file", f);
  const r = await fetch("/upload", {method:"POST", body:fd});
  const j = await r.json();
  ev.target.value = "";
  loadList(j.session);
};

loadList(location.pathname.startsWith("/s/") ? location.pathname.slice(3) : null);
setInterval(loadList, 5000);   // picks up recordings the ESP32 pushes
</script></body></html>"""


def lan_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))        # no packets sent; just picks the route
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


if __name__ == "__main__":
    import uvicorn

    ip = lan_ip()
    print(f"\n  Dashboard   http://{ip}:{PORT}/")
    print(f"  ESP32 posts http://{ip}:{PORT}/ingest")
    print(f"  Put SERVER_HOST \"{ip}\" and SERVER_PORT {PORT} in firmware/src/config.h\n")
    uvicorn.run(app, host="0.0.0.0", port=PORT, log_level="info")
