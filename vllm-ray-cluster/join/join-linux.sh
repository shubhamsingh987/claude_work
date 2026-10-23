#!/usr/bin/env bash
# Join this Linux box (NVIDIA GPU) to the model "party": starts an OpenAI-compatible vLLM server on :8000,
# which the router (webui/server.py) auto-discovers over Tailscale. Usage: bash join-linux.sh [MODEL] [PORT]
# Prereqs: NVIDIA driver (nvidia-smi), Tailscale signed in to the same tailnet.
set -euo pipefail
MODEL="${1:-Qwen/Qwen2.5-1.5B-Instruct}"; PORT="${2:-8000}"

command -v nvidia-smi >/dev/null || { echo "nvidia-smi not found - install the NVIDIA driver"; exit 1; }
command -v tailscale  >/dev/null || { echo "install Tailscale and sign in to the same tailnet"; exit 1; }
TS_IP=$(tailscale ip -4 | head -1); [ -n "$TS_IP" ] || { echo "Tailscale isn't connected"; exit 1; }

export PATH="$HOME/.local/bin:$PATH"
command -v uv >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh
[ -x "$HOME/vllm-env/bin/vllm" ] || { uv venv --python 3.12 "$HOME/vllm-env"; uv pip install -p "$HOME/vllm-env/bin/python" vllm; }

# Open the port only if ufw is active
if command -v ufw >/dev/null && sudo ufw status | grep -q "Status: active"; then sudo ufw allow "$PORT"/tcp; fi

pkill -f "vllm serve" 2>/dev/null || true
export VLLM_USE_FLASHINFER_SAMPLER=0 VLLM_ATTENTION_BACKEND=TRITON_ATTN   # avoids needing nvcc
nohup "$HOME/vllm-env/bin/vllm" serve "$MODEL" --max-model-len 4096 --gpu-memory-utilization 0.8 \
      --enforce-eager --host 0.0.0.0 --port "$PORT" > "$HOME/vllm-join.log" 2>&1 &

echo "Loading $MODEL ... (log: ~/vllm-join.log)"
for _ in $(seq 1 90); do
  curl -sf "http://127.0.0.1:$PORT/v1/models" >/dev/null && { echo "DONE: http://$TS_IP:$PORT/v1 - router will find it within ~10 s"; exit 0; }
  sleep 5
done
echo "Not answering yet - tail ~/vllm-join.log"; exit 1
