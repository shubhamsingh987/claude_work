@echo off
rem Forced command for the "pc-off" SSH key. The key can run only this file.
rem Usage over ssh: off | restart | cancel | status
set "ARG=%SSH_ORIGINAL_COMMAND%"
if /i "%ARG%"=="off"     ( shutdown /s /t 60 /c "Remote shutdown over Tailscale in 60 s (ssh pc-off cancel to stop)" & echo Shutting down in 60 s & exit /b 0 )
if /i "%ARG%"=="restart" ( shutdown /r /t 60 /c "Remote restart over Tailscale in 60 s" & echo Restarting in 60 s & exit /b 0 )
if /i "%ARG%"=="cancel"  ( shutdown /a & echo Cancelled & exit /b 0 )
if /i "%ARG%"=="status"  ( echo PC is on: %COMPUTERNAME% & exit /b 0 )
echo Usage: ssh pc-off off^|restart^|cancel^|status
exit /b 1
