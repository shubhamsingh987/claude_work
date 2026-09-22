#!/bin/bash
# Exit 0 if the voicebot orchestrator is reachable, non-zero otherwise.
# Used from extensions.conf via System() + $SYSTEMSTATUS to gate the call flow.
# Treats ANY http response code (even a 404) as "server is up" -- we don't know
# the orchestrator's exact routes, we just need to know something is listening.
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://192.168.1.31:5000/ 2>/dev/null)
if [ "$CODE" != "000" ] && [ -n "$CODE" ]; then
    exit 0
else
    exit 1
fi
