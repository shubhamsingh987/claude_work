# Run on the host PC. Benchmarks a model on local GPU only, then split 50/50 with the worker PC.
#   .\bench.ps1 -Worker 192.168.1.50            # qwen3:4b
#   .\bench.ps1 -Worker 192.168.1.50 -Model mistral:latest
param(
    [Parameter(Mandatory)][string]$Worker,
    [string]$Model = "qwen3:4b",
    [string]$Bin = "C:\Users\Singh\llama.cpp\bin",
    [string]$Split = "1/1"
)

# Reuse Ollama's already-downloaded GGUF blob instead of re-downloading the model.
$name, $tag = $Model.Split(':')
$manifest = "$env:USERPROFILE\.ollama\models\manifests\registry.ollama.ai\library\$name\$tag"
$digest = ((Get-Content $manifest | ConvertFrom-Json).layers | Where-Object mediaType -eq 'application/vnd.ollama.image.model').digest
$gguf = "$env:USERPROFILE\.ollama\models\blobs\$($digest -replace ':', '-')"

if (-not (Test-NetConnection $Worker -Port 50052 -InformationLevel Quiet)) { throw "Worker $Worker`:50052 not reachable (worker.ps1 running? firewall allowed?)" }

"=== Local GPU only ==="
& "$Bin\llama-bench.exe" -m $gguf -ngl 99 -p 512 -n 128 -r 3 2>&1 | Select-String '\|'
"=== Split $Split with $Worker over network ==="
& "$Bin\llama-bench.exe" -m $gguf -ngl 99 --rpc "$Worker`:50052" -ts $Split -p 512 -n 128 -r 3 2>&1 | Select-String '\|'
