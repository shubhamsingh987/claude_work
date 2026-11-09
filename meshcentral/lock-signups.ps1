# Run elevated AFTER the first (admin) account exists: turns off new sign-ups and restarts MeshCentral.
$cfg = 'C:\Program Files\MeshCentral\meshcentral-data\config.json'
Copy-Item $cfg "$cfg.bak-prelock" -Force
(Get-Content $cfg -Raw) -replace '"newAccounts":\s*true', '"newAccounts": false' | Set-Content $cfg -Encoding ascii
Restart-Service meshcentral.exe
