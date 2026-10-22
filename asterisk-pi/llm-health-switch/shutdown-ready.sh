#!/bin/bash
# Exit 0 only if a clean remote shutdown can actually work: the token file exists on the Pi AND the
# LLM PC's orchestrator has a /shutdown route (a GET to a POST-only Flask route answers 405; 404 = not there).
URL="${LLM_URL:-http://192.168.1.31:5000}"
[ -r /etc/asterisk/llm_shutdown.token ] || exit 1
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "$URL/shutdown")
case "$CODE" in 000|404) exit 1;; *) exit 0;; esac
