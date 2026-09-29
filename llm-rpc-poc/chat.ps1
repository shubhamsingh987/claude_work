# Run on the host PC. Serves a model split across both GPUs with a web chat UI + OpenAI-compatible API.
#   .\chat.ps1 -Worker 192.168.1.50   then open http://localhost:8080
param(
    [Parameter(Mandatory)][string]$Worker,
    [string]$Model = "qwen3:4b",
    [string]$Bin = "C:\Users\Singh\llama.cpp\bin",
    [string]$Split = "1/1"
)

$name, $tag = $Model.Split(':')
$manifest = "$env:USERPROFILE\.ollama\models\manifests\registry.ollama.ai\library\$name\$tag"
$digest = ((Get-Content $manifest | ConvertFrom-Json).layers | Where-Object mediaType -eq 'application/vnd.ollama.image.model').digest
$gguf = "$env:USERPROFILE\.ollama\models\blobs\$($digest -replace ':', '-')"

& "$Bin\llama-server.exe" -m $gguf -ngl 99 --rpc "$Worker`:50052" -ts $Split -c 8192 --port 8080
