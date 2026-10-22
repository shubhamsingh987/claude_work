# Run on the LLM PC. Fixes the duplicate voice_server (NSSM service + scheduled task both launching it)
# and the token file ACL (the SYSTEM-run service could not read it).
$ErrorActionPreference = 'Continue'
$svc = Get-CimInstance Win32_Service | Where-Object { $_.PathName -like '*nssm*' }
foreach ($s in $svc) {
    "service: $($s.Name) | state $($s.State) | start $($s.StartMode) | runs as $($s.StartName)"
    $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.Name)\Parameters"
    if (Test-Path $k) { $p = Get-ItemProperty $k; "  Application: $($p.Application)"; "  AppParameters: $($p.AppParameters)"; "  AppDirectory: $($p.AppDirectory)" }
}
if (-not $svc) { "NO NSSM SERVICE FOUND - aborting before changing anything"; exit 1 }

# 1) token file: SYSTEM + Administrators can read, home keeps full control
$tok = 'C:\Users\home\pbx_box\llm_shutdown.token'
icacls $tok /inheritance:r /grant:r '*S-1-5-18:R' '*S-1-5-32-544:R' 'home:F' | Out-Null
"token ACL: " + ((Get-Acl $tok).Access | ForEach-Object { "$($_.IdentityReference) $($_.FileSystemRights)" }) -join '; '

# 2) disable (not delete) the scheduled task that duplicates the service
Disable-ScheduledTask -TaskName 'VoiceServer' | Out-Null
"scheduled task VoiceServer: " + (Get-ScheduledTask -TaskName 'VoiceServer').State

# 3) stop whatever the task launched (python owned by the user, parent = cmd running start_server.bat)
Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'cmd.exe' -and $_.CommandLine -like '*start_server.bat*' } | ForEach-Object {
    Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $_.ProcessId } | Out-Null
    $cmdPid = $_.ProcessId
    Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $cmdPid } | ForEach-Object { "stopping task child PID $($_.ProcessId) $($_.Name)"; Stop-Process -Id $_.ProcessId -Force }
    "stopping task cmd PID $cmdPid"; Stop-Process -Id $cmdPid -Force
}
Start-Sleep 2

# 4) restart the service so exactly one fresh instance runs with the new permissions
foreach ($s in $svc) { Restart-Service -Name $s.Name -Force; "restarted service $($s.Name)" }
Start-Sleep 5
$py = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'python.exe' -and $_.CommandLine -match 'voice_server\.py' }
"voice_server python processes: " + @($py).Count
$py | ForEach-Object { $o = Invoke-CimMethod -InputObject $_ -MethodName GetOwner; "  PID $($_.ProcessId) owner $($o.Domain)\$($o.User)" }
