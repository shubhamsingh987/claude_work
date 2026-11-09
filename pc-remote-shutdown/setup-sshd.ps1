# Run elevated. Installs OpenSSH Server and authorises ONLY the restricted claude-shutdown key.
param([string]$PubKeyFile, [string]$Log)
$ErrorActionPreference = 'Stop'
Start-Transcript -Path $Log -Force | Out-Null
try {
    $cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*'
    if ($cap.State -ne 'Installed') { Add-WindowsCapability -Online -Name $cap.Name | Out-Null }

    # Start once so sshd generates host keys and the default sshd_config
    Set-Service sshd -StartupType Automatic
    Start-Service sshd; Stop-Service sshd

    $dir = "$env:ProgramData\ssh"
    Copy-Item "$PSScriptRoot\claude-power.ps1" "$dir\claude-power.ps1" -Force
    icacls "$dir\claude-power.ps1" /inheritance:r /grant "*S-1-5-18:F" "*S-1-5-32-544:F" "*S-1-5-11:RX" | Out-Null

    # Key may only run the power script: no shell, no forwarding, no pty
    $pub = (Get-Content $PubKeyFile -Raw).Trim()
    $line = 'restrict,command="powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\ssh\claude-power.ps1" ' + $pub
    $ak = "$dir\administrators_authorized_keys"
    if (Test-Path $ak) { Copy-Item $ak "$ak.bak-preclaude" -Force; $old = Get-Content $ak | Where-Object { $_ -notmatch 'claude-shutdown@' } } else { $old = @() }
    Set-Content -Path $ak -Value (@($old) + $line) -Encoding ascii
    icacls $ak /inheritance:r /grant "*S-1-5-18:F" "*S-1-5-32-544:F" | Out-Null

    # Keys only, no password logins
    $cfg = "$dir\sshd_config"
    Copy-Item $cfg "$cfg.bak-preclaude" -Force
    $c = Get-Content $cfg | Where-Object { $_ -notmatch '^\s*#?\s*PasswordAuthentication\s' }
    Set-Content -Path $cfg -Value (@('PasswordAuthentication no') + $c) -Encoding ascii

    # Firewall: only Tailscale (100.64.0.0/10) and the local subnet
    Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue | Set-NetFirewallRule -RemoteAddress @('100.64.0.0/10','LocalSubnet') -Profile Any
    if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -RemoteAddress @('100.64.0.0/10','LocalSubnet') | Out-Null
    }

    Start-Service sshd
    "SETUP-DONE: sshd $((Get-Service sshd).Status)"
} catch { "SETUP-FAILED: $_" }
Stop-Transcript | Out-Null
