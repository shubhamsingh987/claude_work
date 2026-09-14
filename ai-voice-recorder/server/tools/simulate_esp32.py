"""Pretend to be the ESP32: stream a WAV to /ingest as a chunked POST.

Exercises the exact code path the firmware uses (same headers, same chunked
framing, same 16 kHz mono s16 payload), so you can test the whole server
before the hardware is wired up.

    python tools/simulate_esp32.py sample.wav
    python tools/simulate_esp32.py sample.wav --host 192.168.1.14 --port 8000
"""

from __future__ import annotations

import argparse
import audioop
import socket
import sys
import time
import wave

SAMPLE_RATE = 16000
CHUNK_SAMPLES = 1024                      # matches FRAMES_PER_READ in config.h


def read_as_pcm16k(path: str) -> bytes:
    """Load any PCM WAV and coerce it to 16 kHz mono signed-16 -- the format
    the INMP441 path produces."""
    with wave.open(path, "rb") as w:
        channels, width, rate = w.getnchannels(), w.getsampwidth(), w.getframerate()
        pcm = w.readframes(w.getnframes())

    if width != 2:
        pcm = audioop.lin2lin(pcm, width, 2)
    if channels == 2:
        pcm = audioop.tomono(pcm, 2, 0.5, 0.5)
    elif channels != 1:
        sys.exit(f"cannot handle {channels}-channel audio")
    if rate != SAMPLE_RATE:
        pcm, _ = audioop.ratecv(pcm, 2, 1, rate, SAMPLE_RATE, None)
    return pcm


def stream(pcm: bytes, host: str, port: int, device: str, realtime: bool) -> str:
    sock = socket.create_connection((host, port), timeout=10)
    sock.sendall(
        f"POST /ingest HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        f"User-Agent: esp32-simulator/1.0\r\n"
        f"X-Device-Id: {device}\r\n"
        f"X-Sample-Rate: {SAMPLE_RATE}\r\n"
        f"X-Channels: 1\r\n"
        f"X-Bits: 16\r\n"
        f"Content-Type: application/octet-stream\r\n"
        f"Transfer-Encoding: chunked\r\n"
        f"Connection: close\r\n\r\n".encode()
    )

    step = CHUNK_SAMPLES * 2
    total = len(pcm)
    next_mark = 0
    for off in range(0, total, step):
        block = pcm[off:off + step]
        sock.sendall(b"%X\r\n" % len(block) + block + b"\r\n")
        if realtime:
            time.sleep(len(block) / 2 / SAMPLE_RATE)
        done = min(off + step, total)
        if done >= next_mark:                       # roughly every 10%
            print(f"  streamed {done/1024:7.1f} KB / {total/1024:.1f} KB")
            next_mark += total // 10
    sock.sendall(b"0\r\n\r\n")
    print("  waiting for the server to transcribe and summarise ...")

    sock.settimeout(600)
    buf = b""
    while True:
        part = sock.recv(65536)
        if not part:
            break
        buf += part
    sock.close()

    head, _, body = buf.partition(b"\r\n\r\n")
    print(f"  {head.splitlines()[0].decode(errors='replace')}")
    return body.decode("utf-8", errors="replace")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("wav")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8000)
    ap.add_argument("--device", default="esp32-simulator")
    ap.add_argument("--realtime", action="store_true",
                    help="pace the stream at 1x speed, like the real mic does")
    args = ap.parse_args()

    pcm = read_as_pcm16k(args.wav)
    print(f"  {args.wav}: {len(pcm)/2/SAMPLE_RATE:.1f}s of 16 kHz mono PCM")
    print(stream(pcm, args.host, args.port, args.device, args.realtime))


if __name__ == "__main__":
    main()
