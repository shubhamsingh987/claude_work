# Benchmark results — 2026-10-22

Model `Qwen/Qwen2.5-1.5B-Instruct`, 128 max new tokens, greedy, streaming, client on the same machine as the server.
`--enforce-eager`, Triton attention, FlashInfer sampler off (no nvcc in WSL). Ollama was skipped at the user's request.

| Setup | Conc | TTFT p50 | Aggregate tok/s | Per-request tok/s |
|---|---|---|---|---|
| vLLM PP=2 (3070 + 3050, cross-house) | 1 | 0.041 s | 51.0 | 51.9 |
| | 4 | 0.070 s | 117.6 | 29.9 |
| | 16 | 0.139 s | 412.0 | 26.6 |
| vLLM single GPU (3050, LLM PC) | 1 | 0.036 s | 59.5 | 60.6 |
| | 4 | 0.057 s | 215.9 | 55.3 |
| | 16 | 0.076 s | 832.6 | 53.7 |

Client: `bench.py BASE_URL MODEL LABEL [conc,...]`. Single run each, small sample (8/16/64 requests) — indicative only.
