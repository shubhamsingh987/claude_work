# Forced command for the claude-shutdown SSH key (see README.md).
# The key can only run this script; the word sent over SSH picks the action.
$cmd = "$env:SSH_ORIGINAL_COMMAND".Trim().ToLower()
switch ($cmd) {
    'shutdown' { shutdown.exe /s /t 60 /c "Shutdown requested over SSH (claude-shutdown key)"; "OK: $env:COMPUTERNAME shuts down in 60 s (send 'cancel' to stop it)" }
    'restart'  { shutdown.exe /r /t 60 /c "Restart requested over SSH (claude-shutdown key)";  "OK: $env:COMPUTERNAME restarts in 60 s (send 'cancel' to stop it)" }
    'cancel'   { shutdown.exe /a; if ($LASTEXITCODE -eq 0) { "OK: cancelled" } else { "Nothing to cancel" } }
    default    { "OK: $env:COMPUTERNAME is up. Commands: shutdown, restart, cancel, status" }
}
