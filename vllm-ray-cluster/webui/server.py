"""Serves index.html and proxies /v1/* to the local vLLM server (same origin, so no CORS).

Run: python server.py [port] [upstream]   (defaults: 8080, http://127.0.0.1:8000)
"""
import pathlib
import sys

import aiohttp
from aiohttp import web

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
UPSTREAM = sys.argv[2] if len(sys.argv) > 2 else "http://127.0.0.1:8000"
INDEX = pathlib.Path(__file__).with_name("index.html")


async def index(_):
    return web.FileResponse(INDEX)


async def proxy(request):
    body = await request.read()
    async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=None)) as s:
        async with s.request(request.method, UPSTREAM + request.path_qs, data=body,
                             headers={"Content-Type": request.headers.get("Content-Type", "application/json")}) as r:
            resp = web.StreamResponse(status=r.status, headers={"Content-Type": r.headers.get("Content-Type", "application/json"),
                                                                 "Cache-Control": "no-cache", "X-Accel-Buffering": "no"})
            await resp.prepare(request)
            async for chunk in r.content.iter_any():
                await resp.write(chunk)
            await resp.write_eof()
            return resp


app = web.Application()
app.router.add_get("/", index)
app.router.add_route("*", "/v1/{tail:.*}", proxy)
web.run_app(app, host="0.0.0.0", port=PORT)
