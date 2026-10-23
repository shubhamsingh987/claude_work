"""Tiny OpenAI-compatible streaming benchmark: python bench.py BASE_URL MODEL LABEL [conc,...]"""
import asyncio, json, sys, time, statistics, aiohttp

base, model, label = sys.argv[1], sys.argv[2], sys.argv[3]
concs = [int(c) for c in (sys.argv[4] if len(sys.argv) > 4 else "1,4,16").split(",")]
PROMPT = "Write a detailed explanation of how a refrigerator works, in plain language."
MAX_TOK = 128

async def one(session):
    body = {"model": model, "messages": [{"role": "user", "content": PROMPT}], "max_tokens": MAX_TOK,
            "temperature": 0, "stream": True, "stream_options": {"include_usage": True}}
    t0 = time.perf_counter(); ttft = None; toks = 0
    async with session.post(base + "/v1/chat/completions", json=body) as r:
        async for line in r.content:
            line = line.strip()
            if not line.startswith(b"data:") or line.endswith(b"[DONE]"):
                continue
            d = json.loads(line[5:])
            if d.get("usage"): toks = d["usage"]["completion_tokens"]
            ch = d.get("choices") or []
            if ch and ch[0]["delta"].get("content") and ttft is None:
                ttft = time.perf_counter() - t0
    return ttft or 0, time.perf_counter() - t0, toks

async def run(c):
    n = max(8, 4 * c)
    async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=600)) as s:
        await one(s)  # warm-up
        sem = asyncio.Semaphore(c)
        async def guarded():
            async with sem: return await one(s)
        t0 = time.perf_counter()
        res = await asyncio.gather(*[guarded() for _ in range(n)])
        wall = time.perf_counter() - t0
    tt = sorted(r[0] for r in res); tok = sum(r[2] for r in res)
    print(json.dumps({"label": label, "conc": c, "reqs": n, "ttft_p50_s": round(statistics.median(tt), 3),
                      "ttft_max_s": round(tt[-1], 3), "agg_tok_s": round(tok / wall, 1),
                      "per_req_tok_s": round(statistics.mean(r[2] / (r[1] - r[0]) if r[1] > r[0] else 0 for r in res), 1)}))

for c in concs:
    asyncio.run(run(c))
