# vllm-ray-cluster

Experiment (2026-10-22, "just for fun"): vLLM pipeline-parallel across the user's PC and the LLM PC with Ray,
then compare against Ollama. Real RDMA is impossible (no RDMA NICs on either PC, the PCs are in different houses
and talk over Tailscale, WSL2's stock kernel has no RDMA). Expect the cross-house cluster to be *slower* than one GPU.

## Machines
| | My PC (Ray head) | LLM PC (Ray worker) |
|---|---|---|
| GPU | RTX 3070 Laptop, 8 GB | RTX 3050, 8 GB |
| Tailscale IP | `100.121.120.45` | `100.86.15.30` (`ssh llmpc`) |
| WSL distro | `Ubuntu` (new, 2026-10-22), venv `/opt/venv` (root) | `Ubuntu`, venv `~/vllm-env` (user `home`) |
| `.wslconfig` | `networkingMode=mirrored` (no previous file) | same; no previous file |

vLLM 0.32.0, Ray 2.59.0, torch sees CUDA on both (python 3.12 via `uv`). The LLM PC's `/opt/vllm-env` is the other
chat's broken/partial install (python not executable) — untouched, don't reuse it.

## Gotchas learned
- WSL shuts a distro down when no foreground process remains, which kills a Ray started with plain `ray start`.
  Run Ray with `--block` inside a long-lived hidden `Start-Process wsl ...`.
- Git Bash mangles `/mnt/c/...` paths passed to `wsl`; call `wsl` from PowerShell or put the command in a script.
- ssh to the LLM PC lands in Windows `cmd`; copy `.sh`/`.ps1` files with `scp` (LF endings) instead of quoting.
- A background process started over ssh may die when the ssh session ends — the worker join was not yet confirmed
  persistent at the time of writing.
- `wsl --shutdown` on the LLM PC kills any other chat's work in its Ubuntu distro; check `wsl -l --running` first.

## Commands
Head (my PC, PowerShell): `Start-Process wsl -ArgumentList '-d','Ubuntu','-u','root','--','bash','-c','"/opt/venv/bin/ray start --head --node-ip-address=100.121.120.45 --port=6379 --block"' -WindowStyle Hidden`
Worker: `~/vllm-env/bin/ray start --address=100.121.120.45:6379 --node-ip-address=100.86.15.30 --block` (in LLM PC WSL).
Status: `wsl -d Ubuntu -u root -- /opt/venv/bin/ray status` — a healthy cluster shows 2 nodes, 2 GPUs.
Port 6379 from the worker to the head was verified open.

## WORKING 2026-10-22 13:20 — vLLM pipeline-parallel (PP=2) across both PCs answers requests
`Qwen/Qwen2.5-1.5B-Instruct`, `vllm serve ... --distributed-executor-backend ray --pipeline-parallel-size 2 --enforce-eager`
on head port 8000 (script `%TEMP%\vserve.sh`). Short reply ~0.22 s warm. Fixes that were required:
- NCCL hung at init until pinned to Tailscale: `NCCL_SOCKET_IFNAME` = `eth2` (head) / `eth1` (worker; interface names differ),
  `NCCL_IB_DISABLE=1`, `NCCL_SOCKET_FAMILY=AF_INET`, `GLOO_SOCKET_IFNAME` same. Set in the env of `ray start` on each node.
- Gloo rendezvous needed hostnames -> Tailscale IP in `/etc/hosts` (remove the `127.0.1.1` line); lost when WSL regenerates it.
- No `nvcc` in either WSL -> sampler JIT failed (500 errors). `VLLM_USE_FLASHINFER_SAMPLER=0 VLLM_ATTENTION_BACKEND=TRITON_ATTN`.
- Worker is launched with `rwb2.sh` (NCCL env) on the LLM PC; port 8000 not yet opened in the Hyper-V firewall (8265 is).

## Status / next steps
0. **2026-10-22 12:52: cluster is up** — `ray status` shows 2 nodes, 28 CPU, 2 GPU. The worker survives only because it is
   started via WMI (`Invoke-CimMethod Win32_Process Create 'wsl.exe -d Ubuntu -- bash /mnt/c/Users/home/rwb.sh'`, script runs
   `ray start ... --block`); a plain ssh/Start-Process child dies with the session. Head runs from `rdash.sh` (dashboard :8265,
   needs `ray[default]`, installed on the head only). Dashboard answers 200 inside WSL but the Hyper-V firewall
   (`DefaultInboundAction Block`) stops Windows/browser access — needs a user-approved firewall rule or `Allow`.
1. ~~Confirm both nodes~~ done.
2. Serve a small model (<=3B) with `vllm serve <model> --pipeline-parallel-size 2 --distributed-executor-backend ray`.
3. Benchmark vs single GPU and vs Ollama (TTFT, tok/s at 1/4/16 concurrent). Stop the voicebot's Ollama first (VRAM) —
   that takes the phone assistant offline.
4. Optional later: soft-RoCE needs a custom WSL kernel with `CONFIG_RDMA_RXE` (~30–45 min build); no speed gain expected.
