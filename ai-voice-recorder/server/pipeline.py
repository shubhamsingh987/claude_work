"""Audio -> transcript -> speakers -> notes.

Every stage degrades gracefully: if an optional dependency is missing the
pipeline still returns a result and says, in `meta`, which engine it used.
"""

from __future__ import annotations

import logging
import os
import re
import wave
from collections import Counter
from dataclasses import dataclass, field, asdict
from typing import Any

log = logging.getLogger("pipeline")

WHISPER_MODEL = os.environ.get("WHISPER_MODEL", "base")
WHISPER_DEVICE = os.environ.get("WHISPER_DEVICE", "cpu")
WHISPER_COMPUTE = os.environ.get("WHISPER_COMPUTE", "int8")
SUMMARY_MODEL = os.environ.get("SUMMARY_MODEL", "claude-opus-5")
HF_TOKEN = os.environ.get("HF_TOKEN") or os.environ.get("HUGGINGFACE_TOKEN")


# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------
@dataclass
class Utterance:
    start: float
    end: float
    speaker: str
    text: str


@dataclass
class Result:
    text: str = ""
    language: str = ""
    duration: float = 0.0
    utterances: list[Utterance] = field(default_factory=list)
    speakers: list[str] = field(default_factory=list)
    notes: str = ""
    meta: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["utterances"] = [asdict(u) for u in self.utterances]
        return d


EMBED_RATE = 16000          # what the ECAPA speaker embedder expects


def wav_duration(path: str) -> float:
    with wave.open(path, "rb") as w:
        return w.getnframes() / float(w.getframerate())


def _load_wav_mono(path: str):
    """Read a PCM WAV as float32 mono in [-1, 1]. Avoids torchaudio, whose
    loader now needs TorchCodec, and stdlib `wave` is all we need here."""
    import numpy as np

    with wave.open(path, "rb") as w:
        channels, width, rate = w.getnchannels(), w.getsampwidth(), w.getframerate()
        raw = w.readframes(w.getnframes())

    dtype = {1: np.uint8, 2: np.int16, 4: np.int32}.get(width)
    if dtype is None:
        raise ValueError(f"unsupported sample width: {width} bytes")

    a = np.frombuffer(raw, dtype=dtype).astype(np.float32)
    if width == 1:
        a = (a - 128.0) / 128.0                       # 8-bit WAV is unsigned
    else:
        a /= float(1 << (8 * width - 1))
    if channels > 1:
        a = a.reshape(-1, channels).mean(axis=1)
    return np.ascontiguousarray(a), rate


# ---------------------------------------------------------------------------
# 1. Speech to text (faster-whisper)
# ---------------------------------------------------------------------------
_whisper = None


def _get_whisper():
    global _whisper
    if _whisper is None:
        from faster_whisper import WhisperModel

        log.info("loading whisper model %r (%s/%s) - first run downloads it",
                 WHISPER_MODEL, WHISPER_DEVICE, WHISPER_COMPUTE)
        _whisper = WhisperModel(WHISPER_MODEL, device=WHISPER_DEVICE,
                                compute_type=WHISPER_COMPUTE)
        log.info("whisper ready")
    return _whisper


def transcribe(wav_path: str) -> tuple[list[dict], str]:
    """Returns (segments, detected_language). Segments are dicts with
    start/end/text, ordered in time."""
    model = _get_whisper()
    segments, info = model.transcribe(
        wav_path,
        beam_size=5,
        vad_filter=True,                      # drops the silence between turns
        vad_parameters={"min_silence_duration_ms": 400},
    )
    out = []
    for s in segments:
        text = s.text.strip()
        if text:
            out.append({"start": round(s.start, 2), "end": round(s.end, 2),
                        "text": text})
    return out, getattr(info, "language", "") or ""


# ---------------------------------------------------------------------------
# 2. Speaker separation
#
# Three engines, best first. Whichever is available wins; the name of the one
# that ran is reported back to the caller so the UI never implies more
# precision than was actually applied.
# ---------------------------------------------------------------------------
_diarizer = None
_embedder = None


def _pyannote_turns(wav_path: str) -> list[dict] | None:
    """Real diarization. Needs `pyannote.audio` plus an HF token with the
    pyannote/speaker-diarization-3.1 licence accepted."""
    global _diarizer
    if not HF_TOKEN:
        return None
    try:
        if _diarizer is None:
            from pyannote.audio import Pipeline as PyannotePipeline

            log.info("loading pyannote speaker-diarization-3.1")
            _diarizer = PyannotePipeline.from_pretrained(
                "pyannote/speaker-diarization-3.1", use_auth_token=HF_TOKEN)
        annotation = _diarizer(wav_path)
    except Exception as exc:                          # noqa: BLE001
        log.warning("pyannote unavailable (%s)", exc)
        return None

    return [{"start": float(seg.start), "end": float(seg.end),
             "speaker": str(label)}
            for seg, _, label in annotation.itertracks(yield_label=True)]


def _embedding_speakers(wav_path: str, segments: list[dict]) -> list[str] | None:
    """Fallback: one ECAPA voice embedding per transcript segment, then
    agglomerative clustering. Coarser than pyannote (it cannot split a segment
    where two people overlap) but needs no gated model."""
    if len(segments) < 2:
        return None
    try:
        import numpy as np
        import torch
        from sklearn.cluster import AgglomerativeClustering
        from speechbrain.inference.speaker import EncoderClassifier
    except Exception:                                  # noqa: BLE001
        return None

    global _embedder
    try:
        if _embedder is None:
            kwargs = {"source": "speechbrain/spkrec-ecapa-voxceleb",
                      "savedir": os.path.join("models", "ecapa")}
            try:
                # SpeechBrain symlinks the HF cache by default, which needs
                # developer mode / admin rights on Windows. Copy instead.
                from speechbrain.utils.fetching import LocalStrategy

                kwargs["local_strategy"] = LocalStrategy.COPY
            except ImportError:
                pass
            log.info("loading ECAPA speaker embedder")
            _embedder = EncoderClassifier.from_hparams(**kwargs)

        wav, sr = _load_wav_mono(wav_path)             # float32 in [-1, 1]
        if sr != EMBED_RATE:                           # ECAPA wants 16 kHz
            n = int(round(len(wav) * EMBED_RATE / sr))
            wav = np.interp(np.linspace(0, len(wav) - 1, n),
                            np.arange(len(wav)), wav).astype(np.float32)
            sr = EMBED_RATE

        vecs, keep = [], []
        for i, seg in enumerate(segments):
            a, b = int(seg["start"] * sr), int(seg["end"] * sr)
            clip = wav[a:b]
            if len(clip) < sr * 0.4:                   # <400 ms is too short
                continue
            with torch.no_grad():
                emb = _embedder.encode_batch(
                    torch.from_numpy(clip).unsqueeze(0)).squeeze()
            vecs.append(emb.cpu().numpy())
            keep.append(i)

        if len(vecs) < 2:
            return None

        X = np.vstack(vecs)
        X /= (np.linalg.norm(X, axis=1, keepdims=True) + 1e-9)
        labels = AgglomerativeClustering(
            n_clusters=None, distance_threshold=0.75,
            metric="cosine", linkage="average").fit_predict(X)

        speakers = ["SPEAKER_00"] * len(segments)
        for idx, lab in zip(keep, labels):
            speakers[idx] = f"SPEAKER_{lab:02d}"
        # Segments too short to embed inherit their predecessor's speaker.
        last = speakers[keep[0]] if keep else "SPEAKER_00"
        for i in range(len(speakers)):
            if i in keep:
                last = speakers[i]
            else:
                speakers[i] = last
        return speakers
    except Exception as exc:                           # noqa: BLE001
        log.warning("embedding diarization failed (%s)", exc)
        return None


def _assign_by_overlap(segments: list[dict], turns: list[dict]) -> list[str]:
    """Give each transcript segment the speaker it overlaps with most."""
    out = []
    for seg in segments:
        best, best_overlap = "SPEAKER_00", 0.0
        for turn in turns:
            overlap = min(seg["end"], turn["end"]) - max(seg["start"], turn["start"])
            if overlap > best_overlap:
                best, best_overlap = turn["speaker"], overlap
        out.append(best)
    return out


def diarize(wav_path: str, segments: list[dict]) -> tuple[list[str], str]:
    """Returns (one speaker label per segment, engine name)."""
    turns = _pyannote_turns(wav_path)
    if turns:
        return _assign_by_overlap(segments, turns), "pyannote"

    speakers = _embedding_speakers(wav_path, segments)
    if speakers:
        return speakers, "ecapa-clustering"

    return ["SPEAKER_00"] * len(segments), "none"


# ---------------------------------------------------------------------------
# 3. Notes
# ---------------------------------------------------------------------------
SUMMARY_SYSTEM = """You turn raw meeting and voice-memo transcripts into notes.

The transcript comes from an automatic recogniser, so expect mis-heard words,
missing punctuation, and imperfect speaker labels. Read through the errors;
never quote a garbled phrase as if it were verbatim.

Write the notes as markdown with these sections, omitting any that the
transcript genuinely has nothing for:

## Summary
Two to four sentences on what was actually discussed.

## Key points
Bullets, grouped by topic when there is more than one.

## Decisions
Only things that were actually settled.

## Action items
`- [ ] owner - task` , using the speaker label when no name was said. Leave
this section out entirely rather than inventing tasks.

## Open questions
Anything raised and left unresolved.

Be concise and concrete. Do not pad, do not add a preamble, and do not
speculate beyond what was said."""


def _fallback_notes(utterances: list[Utterance], reason: str) -> str:
    """Extractive notes when the API is unavailable: highest-scoring sentences
    by content-word frequency, plus anything that looks like a commitment."""
    text = " ".join(u.text for u in utterances).strip()
    if not text:
        return "_No speech detected._"

    sentences = [s.strip() for s in re.split(r"(?<=[.!?])\s+", text) if s.strip()]
    stop = set("""a an the and or but if of to in on at for with is are was were be been
                  being it its this that these those i you he she we they me him her us them
                  my your his their our so as by from not no do does did have has had will
                  would can could should just like really very there here what when where
                  who how why um uh yeah okay ok""".split())
    freq = Counter(w for w in re.findall(r"[a-z']+", text.lower())
                   if w not in stop and len(w) > 2)

    def score(s: str) -> float:
        words = re.findall(r"[a-z']+", s.lower())
        return sum(freq[w] for w in words) / (len(words) ** 0.5 + 1e-9)

    top = sorted(sorted(sentences, key=score, reverse=True)[:6],
                 key=sentences.index)
    action_re = re.compile(
        r"\b(need to|needs to|have to|has to|let's|lets|will|should|todo|to-do|"
        r"action item|follow up|follow-up|deadline|by (monday|tuesday|wednesday|"
        r"thursday|friday|saturday|sunday|tomorrow|next week))\b", re.I)
    actions = [s for s in sentences if action_re.search(s)][:8]

    parts = [f"> Extractive notes only - {reason}.", "", "## Summary", ""]
    parts.append(" ".join(top) if top else text[:600])
    parts += ["", "## Key points", ""]
    parts += [f"- {s}" for s in top] or ["- (none extracted)"]
    if actions:
        parts += ["", "## Possible action items", ""]
        parts += [f"- [ ] {s}" for s in actions]
    return "\n".join(parts)


def summarize(utterances: list[Utterance], duration: float) -> tuple[str, str]:
    """Returns (markdown notes, engine name)."""
    if not utterances:
        return "_No speech detected._", "none"

    transcript = "\n".join(
        f"[{u.start:7.2f}s] {u.speaker}: {u.text}" for u in utterances)
    speakers = sorted({u.speaker for u in utterances})

    if not os.environ.get("ANTHROPIC_API_KEY"):
        return _fallback_notes(utterances, "ANTHROPIC_API_KEY is not set"), "extractive"

    try:
        import anthropic

        client = anthropic.Anthropic()
        prompt = (
            f"Recording length: {duration:.0f}s. "
            f"Distinct speaker labels detected: {', '.join(speakers)}.\n\n"
            f"Transcript:\n\n{transcript}\n\nWrite the notes.")

        response = client.beta.messages.create(
            model=SUMMARY_MODEL,
            max_tokens=16000,
            system=SUMMARY_SYSTEM,
            thinking={"type": "adaptive"},
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
            messages=[{"role": "user", "content": prompt}],
        )
        if response.stop_reason == "refusal":
            return (_fallback_notes(utterances, "the model declined this transcript"),
                    "extractive")

        notes = "".join(b.text for b in response.content if b.type == "text").strip()
        return (notes, response.model) if notes else (
            _fallback_notes(utterances, "the model returned no text"), "extractive")

    except Exception as exc:                           # noqa: BLE001
        log.warning("summarisation failed: %s", exc)
        return _fallback_notes(utterances, f"summariser error: {exc}"), "extractive"


# ---------------------------------------------------------------------------
# Full run
# ---------------------------------------------------------------------------
def process(wav_path: str) -> Result:
    duration = wav_duration(wav_path)
    log.info("transcribing %s (%.1fs)", os.path.basename(wav_path), duration)

    segments, language = transcribe(wav_path)
    log.info("%d segments, language=%s", len(segments), language)

    speakers, diar_engine = diarize(wav_path, segments)
    log.info("speaker separation via %s", diar_engine)

    utterances = [
        Utterance(start=s["start"], end=s["end"], speaker=spk, text=s["text"])
        for s, spk in zip(segments, speakers)
    ]

    notes, summary_engine = summarize(utterances, duration)
    log.info("notes via %s", summary_engine)

    return Result(
        text=" ".join(u.text for u in utterances),
        language=language,
        duration=round(duration, 2),
        utterances=utterances,
        speakers=sorted({u.speaker for u in utterances}),
        notes=notes,
        meta={
            "asr": f"faster-whisper:{WHISPER_MODEL}",
            "diarization": diar_engine,
            "summarizer": summary_engine,
        },
    )
