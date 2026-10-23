<#
Join this Windows PC (NVIDIA GPU) to the model "party": it starts an OpenAI-compatible vLLM server on port 8000,
and the router (webui/server.py) auto-discovers it within ~10 s - nothing to register.

Run once, in a normal PowerShell:   powershell -ExecutionPolicy Bypass -File join-windows.ps1 [-Model Qwen/Qwen2.5-1.5B-Instruct] [-Port 8000] [-Autostart]
It asks for admin (needed once for the firewall rule + WSL feature). Prereqs: Windows 11/10 with WSL2 support, an NVIDIA driver
(nvidia-smi works), and Tailscale installed and signed in to the SAME tailnet as the router.
#>
param(
    [string]$Model = "Qwen/Qwen2.5-1.5B-Instruct",
    [int]$Port = 8000,
    [double]$GpuMemUtil = 0.8,
    [switch]$Autostart
)
$ErrorActionPreference = "Stop"

# --- self-elevate (firewall rules need admin) ---------------------------------------------------------------------
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole("Administrator")
if (-not $admin) {
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"", "-Model", $Model, "-Port", $Port, "-GpuMemUtil", $GpuMemUtil)
    if ($Autostart) { $argList += "-Autostart" }
    Start-Process powershell -Verb RunAs -ArgumentList $argList
    exit
}

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }

# --- checks -------------------------------------------------------------------------------------------------------
Step "Checking GPU and Tailscale"
if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) { throw "nvidia-smi not found - install the NVIDIA driver first." }
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
if (-not (Get-Command tailscale -ErrorAction SilentlyContinue)) { throw "Tailscale not installed - get it from tailscale.com and sign in to your tailnet." }
$ts = tailscale status 2>&1 | Out-String
if ($ts -match "stopped|Logged out|NeedsLogin") { throw "Tailscale isn't connected. Open it, sign in to the same tailnet, then rerun." }
$tsIp = (tailscale ip -4 | Select-Object -First 1).Trim()
Write-Host "Tailscale IP: $tsIp"

# --- WSL + mirrored networking -------------------------------------------------------------------------------------
Step "Setting up WSL (Ubuntu)"
$distros = (wsl -l -q 2>$null | Out-String) -replace "`0", ""
if ($distros -notmatch "Ubuntu") { wsl --install Ubuntu --no-launch; if ($LASTEXITCODE -ne 0) { throw "WSL install failed (a reboot may be needed - reboot and rerun)." } }

$cfg = Join-Path $env:USERPROFILE ".wslconfig"
$needShutdown = $false
if (-not (Test-Path $cfg) -or (Get-Content $cfg -Raw) -notmatch "networkingMode\s*=\s*mirrored") {
    if (Test-Path $cfg) { Copy-Item $cfg "$cfg.bak-join" -Force; Write-Host "Backed up existing .wslconfig to .wslconfig.bak-join" }
    Add-Content $cfg "`n[wsl2]`nnetworkingMode=mirrored`n"   # mirrored networking: WSL shares the Windows Tailscale/LAN IPs
    $needShutdown = $true
}
if ($needShutdown) { wsl --shutdown; Start-Sleep 5 }

# --- firewall: Hyper-V (WSL mirrored) + regular Windows ------------------------------------------------------------
Step "Opening TCP $Port"
$vmCreator = '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}'   # WSL's well-known VM creator id
if (-not (Get-NetFirewallHyperVRule -Name "vLLM-$Port" -ErrorAction SilentlyContinue)) {
    New-NetFirewallHyperVRule -Name "vLLM-$Port" -DisplayName "vLLM $Port" -Direction Inbound -VMCreatorId $vmCreator -Protocol TCP -LocalPorts $Port -Action Allow | Out-Null
}
if (-not (Get-NetFirewallRule -DisplayName "vLLM $Port" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "vLLM $Port" -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -Profile Any | Out-Null
}

# --- install vLLM inside WSL (idempotent) --------------------------------------------------------------------------
Step "Installing vLLM in WSL (first run downloads several GB)"
$setup = @'
set -e
export PATH=$HOME/.local/bin:$PATH
command -v curl >/dev/null || (apt-get update -qq && apt-get install -y -qq curl ca-certificates)
command -v uv >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh
[ -x $HOME/vllm-env/bin/vllm ] || { uv venv --python 3.12 $HOME/vllm-env; uv pip install -p $HOME/vllm-env/bin/python vllm; }
$HOME/vllm-env/bin/python -c "import torch;print('CUDA available:', torch.cuda.is_available())"
'@
$serve = @"
export VLLM_USE_FLASHINFER_SAMPLER=0 VLLM_ATTENTION_BACKEND=TRITON_ATTN
exec `$HOME/vllm-env/bin/vllm serve $Model --max-model-len 4096 --gpu-memory-utilization $GpuMemUtil --enforce-eager --host 0.0.0.0 --port $Port > `$HOME/vllm-join.log 2>&1
"@
$dir = Join-Path $env:LOCALAPPDATA "vllm-join"; New-Item -ItemType Directory -Force $dir | Out-Null
$setup -replace "`r", "" | Set-Content (Join-Path $dir "setup.sh") -NoNewline -Encoding ascii
$serve -replace "`r", "" | Set-Content (Join-Path $dir "serve.sh") -NoNewline -Encoding ascii
$setupWsl = (wsl -d Ubuntu -u root -- wslpath -a ($dir -replace '\\', '/') | Out-String).Trim()
wsl -d Ubuntu -u root -- bash "$setupWsl/setup.sh"
if ($LASTEXITCODE -ne 0) { throw "vLLM install failed - see output above." }

# --- start the server (a hidden wsl process keeps the VM alive) ----------------------------------------------------
Step "Starting the server"
wsl -d Ubuntu -u root -- pkill -f "vllm serve" 2>$null
Start-Process wsl -ArgumentList "-d", "Ubuntu", "-u", "root", "--", "bash", "$setupWsl/serve.sh" -WindowStyle Hidden

if ($Autostart) {
    $act = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d Ubuntu -u root -- bash $setupWsl/serve.sh"
    Register-ScheduledTask -TaskName "vLLM-join" -Action $act -Trigger (New-ScheduledTaskTrigger -AtLogOn) -Force | Out-Null
    Write-Host "Autostart registered (runs at logon)."
}

Write-Host "Waiting for the model to load (log: wsl cat ~/vllm-join.log)..."
$ok = $false
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep 5
    try { if ((Invoke-WebRequest "http://127.0.0.1:$Port/v1/models" -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200) { $ok = $true; break } } catch {}
}
if (-not $ok) { Write-Warning "Not answering yet - check: wsl -d Ubuntu -u root -- tail -f /root/vllm-join.log"; exit 1 }
Write-Host "`nDONE. This PC now serves $Model at http://${tsIp}:$Port/v1" -ForegroundColor Green
Write-Host "The router finds it automatically within ~10 s. Keep this PC awake."
