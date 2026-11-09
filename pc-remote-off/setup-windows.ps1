# Run on the Windows PC in an ELEVATED PowerShell:
#   powershell -ExecutionPolicy Bypass -File setup-windows.ps1 -PubKey "ssh-ed25519 AAAA... pi-pc-off"
# Installs OpenSSH Server, allows it only from Tailscale (100.64.0.0/10), and authorises ONE key
# that can only run pc-power.cmd (off / restart / cancel / status). No shell access.
param([Parameter(Mandatory)][string]$PubKey)
$ErrorActionPreference = 'Stop'

$cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*'
if ($cap.State -ne 'Installed') { Add-WindowsCapability -Online -Name $cap.Name | Out-Null }
Set-Service sshd -StartupType Automatic
Start-Service sshd

# Firewall: Tailscale addresses only. Disable the default allow-all rule.
Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue | Disable-NetFirewallRule
if (-not (Get-NetFirewallRule -Name 'sshd-tailscale-only' -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name 'sshd-tailscale-only' -DisplayName 'OpenSSH (Tailscale only)' `
    -Direction Inbound -Protocol TCP -LocalPort 22 -RemoteAddress 100.64.0.0/10 -Action Allow | Out-Null
}

# Forced-command script
$dir = 'C:\ProgramData\ssh'
Copy-Item -Force (Join-Path $PSScriptRoot 'pc-power.cmd') "$dir\pc-power.cmd"

# Admin accounts read keys from administrators_authorized_keys (not ~/.ssh)
$line = "command=""$dir\pc-power.cmd"",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty $($PubKey.Trim())"
$ak = "$dir\administrators_authorized_keys"
if (-not (Test-Path $ak) -or -not (Select-String -Path $ak -SimpleMatch $PubKey.Trim() -Quiet)) {
  Add-Content -Path $ak -Value $line -Encoding ascii
}
icacls $ak /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null
icacls "$dir\pc-power.cmd" /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' /grant '*S-1-5-32-545:RX' | Out-Null

Restart-Service sshd
Write-Host "Done. Windows user for SSH: $env:USERNAME   Tailscale IP: $((tailscale ip -4) 2>$null)"
