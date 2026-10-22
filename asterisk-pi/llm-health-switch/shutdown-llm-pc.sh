#!/bin/bash
# Gracefully shuts down the LLM PC, then cuts its smart plug -- but ONLY after the PC has really
# gone quiet. If the clean shutdown can't be requested, the plug is left alone (a hard power cut on
# a running Windows PC can corrupt files).
#
# Needs (created by the USER, never an agent):
#   /etc/asterisk/llm_shutdown.token   one line: shared secret the PC's /shutdown route checks
# Pi side calls:  POST http://192.168.1.31:5000/shutdown   header  X-Token: <secret>
# Exit codes: 0 = shut down and plug off, 1 = clean shutdown not possible (plug untouched),
#             2 = shutdown requested but the PC never went down (plug untouched), 3 = plug failed.
URL="${LLM_URL:-http://192.168.1.31:5000}"
TOKEN_FILE=/etc/asterisk/llm_shutdown.token
log(){ logger -t llm-shutdown "$*"; }

[ -r "$TOKEN_FILE" ] || { log "no $TOKEN_FILE; refusing to cut power"; exit 1; }
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -X POST -H "X-Token: $(cat "$TOKEN_FILE")" "$URL/shutdown")
if [ "$CODE" != "200" ] && [ "$CODE" != "202" ]; then log "shutdown request refused (HTTP $CODE); plug untouched"; exit 1; fi
log "shutdown requested (HTTP $CODE); waiting for the PC to go down"

# Wait until the orchestrator stops answering, then give Windows time to finish powering off.
for i in $(seq 1 24); do          # up to ~2 min, every 5 s
  sleep 5
  if [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$URL/")" = "000" ]; then DOWN=1; break; fi
done
[ -n "$DOWN" ] || { log "PC still answering after 2 min; plug untouched"; exit 2; }
sleep 40                           # Windows keeps shutting down after the web server stops
/usr/local/bin/turn-on-tuya.sh off && { log "PC down and plug off"; exit 0; } || { log "plug off FAILED"; exit 3; }
