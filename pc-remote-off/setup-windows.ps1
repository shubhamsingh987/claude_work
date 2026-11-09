# Run on the Windows PC in an ELEVATED PowerShell:
#   powershell -ExecutionPolicy Bypass -File setup-windows.ps1 -PubKey "ssh-ed25519 AAAA... (iPhone Shortcuts key)"
# Installs OpenSSH Server, allows it only from Tailscale (100.64.0.0/10), and authorises ONE key
# that can only run pc-power.cmd (off / restart / cancel / status). No shell access.
param([Parameter(Mandatory)][string]$PubKey)
$ErrorActionPreference = 'Stop'

$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run this from an elevated PowerShell (right-click > Run as administrator).'
}
if ($PubKey -notmatch '^\s*(ssh-ed25519|ecdsa-sha2-nistp\d+|ssh-rsa) [A-Za-z0-9+/=]+') {
  throw 'PubKey does not look like an SSH public key (expected "ssh-ed25519 AAAA...").'
}

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
New-Item -ItemType Directory -Force $dir | Out-Null
Copy-Item -Force (Join-Path $PSScriptRoot 'pc-power.cmd') "$dir\pc-power.cmd"

# The user running this (elevated) is an administrator, and sshd reads admins' keys only from
# C:\ProgramData\ssh\administrators_authorized_keys (not ~\.ssh). Run it as the account the iPhone will log in as.
# ACLs use SIDs so this works on non-English Windows (S-1-5-32-544 Administrators, S-1-5-18 SYSTEM, S-1-5-32-545 Users).
$key  = $PubKey.Trim()
$line = "command=""$dir\pc-power.cmd"",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty $key"
$ak = "$dir\administrators_authorized_keys"
if (-not (Test-Path $ak) -or -not (Select-String -Path $ak -SimpleMatch $key -Quiet)) {
  Add-Content -Path $ak -Value $line -Encoding ascii
}
icacls $ak /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F' | Out-Null
icacls "$dir\pc-power.cmd" /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F' /grant '*S-1-5-32-545:RX' | Out-Null

Restart-Service sshd
$ts = $null
try { $ts = (& tailscale ip -4 2>$null | Select-Object -First 1) } catch {}
if (-not $ts) { Write-Warning "Tailscale CLI not found or not connected - check the PC is on the tailnet." }
Write-Host "Done. Key added to: $ak"
Write-Host "In the Shortcut use  User: $env:USERNAME   Host: $ts   Port: 22"
