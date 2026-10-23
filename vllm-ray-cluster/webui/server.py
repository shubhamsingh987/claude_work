"""Chat web UI + auto-discovering router for OpenAI-compatible backends (vLLM, Ollama, ...).

Every DISCOVER_EVERY seconds it asks Tailscale for the online peers and probes each one (plus localhost) on a few
ports for GET /v1/models. Anything that answers becomes a backend; requests go to a backend that serves the
requested model, picking the one with the fewest requests in flight. A new server joins by simply being on the
tailnet with an OpenAI-compatible server on one of PROBE_PORTS (and the port open in its firewall) - nothing to register.

Run: python server.py [port]        env: PROBE_PORTS=8000,8001,11434  DISCOVER_EVERY=10  TAILSCALE=<path to tailscale CLI>
"""
import asyncio
import json
import os
import pathlib
import shutil
import sys
import time

import aiohttp
from aiohttp import web

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
PROBE_PORTS = [int(p) for p in os.environ.get("PROBE_PORTS", "8000,8001,11434").split(",")]
EVERY = int(os.environ.get("DISCOVER_EVERY", "10"))
TAILSCALE = os.environ.get("TAILSCALE") or shutil.which("tailscale") or shutil.which("tailscale.exe") \
    or "/mnt/c/Program Files/Tailscale/tailscale.exe"
INDEX = pathlib.Path(__file__).with_name("index.html")

backends = {}  # base url -> {"models": [...], "inflight": int, "seen": float, "name": str}


async def tailnet_peers():
    """[(name, ip)] of online tailnet peers, plus localhost."""
    peers = [("localhost", "127.0.0.1")]
    try:
        p = await asyncio.create_subprocess_exec(TAILSCALE, "status", "--json",
                                                 stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
        out, _ = await p.communicate()
        data = json.loads(out.decode("utf-8-sig"))
        for node in (data.get("Peer") or {}).values():   # Self is covered by the localhost probe
            ips = [i for i in node.get("TailscaleIPs", []) if "." in i]
            if ips and node.get("Online"):
                peers.append((node.get("HostName", ips[0]), ips[0]))
    except Exception as e:  # tailscale CLI missing etc. - localhost-only still works
        print("tailscale status failed:", e, flush=True)
    return peers


async def probe(session, name, ip, port):
    base = f"http://{ip}:{port}"
    try:
        async with session.get(base + "/v1/models", timeout=aiohttp.ClientTimeout(total=2)) as r:
            if r.status == 200:
                models = [m["id"] for m in (await r.json()).get("data", [])]
                if models:
                    return base, name, models
    except Exception:
        pass
    return None


async def discover_loop(app):
    async with aiohttp.ClientSession() as session:
        while True:
            peers = await tailnet_peers()
            found = await asyncio.gather(*[probe(session, n, ip, p) for n, ip in peers for p in PROBE_PORTS])
            now = time.time()
            for hit in filter(None, found):
                base, name, models = hit
                b = backends.setdefault(base, {"inflight": 0})
                if "models" not in b:
                    print(f"+ backend {base} ({name}) models={models}", flush=True)
                b.update(models=models, seen=now, name=name)
            for base in [b for b, v in backends.items() if now - v["seen"] > 3 * EVERY]:
                print(f"- backend {base} gone", flush=True)
                del backends[base]
            await asyncio.sleep(EVERY)


async def start_discovery(app):
    app["discovery"] = asyncio.create_task(discover_loop(app))


def pick(model):
    cands = [(v["inflight"], b) for b, v in backends.items() if model in v["models"]]
    return min(cands)[1] if cands else None


async def index(_):
    return web.FileResponse(INDEX)


async def models(_):
    ids = sorted({m for v in backends.values() for m in v["models"]})
    return web.json_response({"object": "list", "data": [{"id": m, "object": "model"} for m in ids]})


async def status(_):
    return web.json_response({b: {"name": v["name"], "models": v["models"], "inflight": v["inflight"]}
                              for b, v in backends.items()})


async def proxy(request):
    body = await request.read()
    model = ""
    try:
        model = json.loads(body).get("model", "") if body else ""
    except ValueError:
        pass
    base = pick(model) or (min((v["inflight"], b) for b, v in backends.items())[1] if backends else None)
    if not base:
        return web.json_response({"error": "no backends discovered yet"}, status=503)
    backends[base]["inflight"] += 1
    try:
        async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=None)) as s:
            async with s.request(request.method, base + request.path_qs, data=body,
                                 headers={"Content-Type": request.headers.get("Content-Type", "application/json")}) as r:
                resp = web.StreamResponse(status=r.status, headers={
                    "Content-Type": r.headers.get("Content-Type", "application/json"),
                    "Cache-Control": "no-cache", "X-Accel-Buffering": "no", "X-Backend": base})
                await resp.prepare(request)
                async for chunk in r.content.iter_any():
                    await resp.write(chunk)
                await resp.write_eof()
                return resp
    finally:
        if base in backends:
            backends[base]["inflight"] -= 1


app = web.Application()
app.on_startup.append(start_discovery)
app.router.add_get("/", index)
app.router.add_get("/v1/models", models)
app.router.add_get("/backends", status)
app.router.add_route("*", "/v1/{tail:.*}", proxy)
web.run_app(app, host="0.0.0.0", port=PORT)
