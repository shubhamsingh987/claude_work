# Run elevated. Installs MeshCentral (pinned) as a Windows service on this PC.
# Web UI: https://shubham-1.tail5cad5d.ts.net:8443  (Tailscale + local subnet only)
param([string]$Log, [string]$Version = '1.3.1')
$ErrorActionPreference = 'Stop'
Start-Transcript -Path $Log -Force | Out-Null
try {
    $dir = 'C:\Program Files\MeshCentral'
    New-Item -ItemType Directory -Force "$dir\meshcentral-data" | Out-Null
    Set-Location $dir

    if (-not (Test-Path "$dir\meshcentral-data\config.json")) {
        Copy-Item "$PSScriptRoot\config.json" "$dir\meshcentral-data\config.json"
    }

    if (-not (Test-Path "$dir\package.json")) { '{"name":"meshcentral-host","private":true}' | Set-Content package.json -Encoding ascii }
    # Through cmd so npm's stderr warnings aren't fatal under PS 5.1 + Stop
    cmd /c "npm install --no-fund --no-audit meshcentral@$Version 2>&1" | Out-String | Write-Output
    if (-not (Test-Path "$dir\node_modules\meshcentral\meshcentral.js")) { throw 'npm install failed' }

    # First run as a normal process creates certificates + pulls optional modules, then install the service
    # The first --install may only fetch node-windows and ask for a rerun, so try up to 3 times
    $svc = $null
    foreach ($i in 1..3) {
        cmd /c "node node_modules\meshcentral --install 2>&1" | Out-String | Write-Output
        Start-Sleep 5
        $svc = Get-Service -Name 'MeshCentral*' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($svc) { break }
    }
    if (-not $svc) { throw 'MeshCentral service was not created' }
    Set-Service $svc.Name -StartupType Automatic
    if ($svc.Status -ne 'Running') { Start-Service $svc.Name }

    if (-not (Get-NetFirewallRule -Name 'MeshCentral-8443' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name 'MeshCentral-8443' -DisplayName 'MeshCentral (8443, Tailscale + LAN only)' -Direction Inbound -Protocol TCP -LocalPort 8443 -Action Allow -RemoteAddress @('100.64.0.0/10','LocalSubnet') -Profile Any | Out-Null
    }
    "SETUP-DONE: service $($svc.Name) $((Get-Service $svc.Name).Status)"
} catch { "SETUP-FAILED: $_" }
Stop-Transcript | Out-Null
