# Run on PC #2 (the GPU "donor"). Exposes its GPU to the host PC over the LAN.
# Needs llama.cpp CUDA build unzipped to C:\llama.cpp\bin (both zips: llama-*-cuda-13.4 + cudart-*-13.4).
# On first run Windows Firewall pops up: allow on PRIVATE networks only.
# SECURITY: rpc-server has no authentication — anyone on the LAN can use it. Only run on a trusted network, stop it after.
param([string]$Bin = "C:\llama.cpp\bin", [int]$Port = 50052)

Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.*' -and $_.InterfaceAlias -notlike 'vEthernet*' } |
    ForEach-Object { "Reachable at $($_.IPAddress):$Port  ($($_.InterfaceAlias))" }

& "$Bin\ggml-rpc-server.exe" -H 0.0.0.0 -p $Port -c
