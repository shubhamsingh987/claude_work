@echo off
rem Forced command for the iPhone "PC Off" SSH key. The key can run only this file.
rem Words: off | restart | cancel | status
rem Delayed expansion (!VAR!) is used on purpose: the command text is never re-parsed by cmd,
rem so characters like & | " in it cannot run anything else.
setlocal EnableExtensions EnableDelayedExpansion
set "ARG=" & set "WORD="
if defined SSH_ORIGINAL_COMMAND set "ARG=!SSH_ORIGINAL_COMMAND!"
rem Keep only the first word (drops stray spaces/newlines the Shortcut may add).
if defined ARG for /f "tokens=1" %%A in ("!ARG!") do if not defined WORD set "WORD=%%A"
if /i "!WORD!"=="off"     ( shutdown /s /t 60 /c "Remote shutdown over Tailscale in 60 s - run PC Cancel to stop" & echo Shutting down in 60 s & exit /b 0 )
if /i "!WORD!"=="restart" ( shutdown /r /t 60 /c "Remote restart over Tailscale in 60 s - run PC Cancel to stop" & echo Restarting in 60 s & exit /b 0 )
if /i "!WORD!"=="cancel"  ( shutdown /a >/dev/null 2>&1 && echo Cancelled || echo Nothing to cancel & exit /b 0 )
if /i "!WORD!"=="status"  ( echo PC is on: %COMPUTERNAME% & exit /b 0 )
echo Refused. Allowed words: off, restart, cancel, status
exit /b 1
