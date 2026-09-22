#!/bin/bash
# Calls Home Assistant's REST API to turn on the "home switch".
# Reads the HA long-lived access token from a file the USER creates and places
# here directly -- never generated, typed, or embedded by the assistant. See
# asterisk-pi/SETUP.md for how to create it.
TOKEN_FILE="/etc/asterisk/ha_token.secret"
HA_URL="http://192.168.1.131:8123"
ENTITY_ID="switch.home_switch"

if [ ! -f "$TOKEN_FILE" ]; then
    logger -t home-switch "Token file $TOKEN_FILE not found -- has it been created yet?"
    exit 1
fi

TOKEN=$(cat "$TOKEN_FILE")

RESPONSE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
    -X POST "$HA_URL/api/services/switch/turn_on" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"entity_id\": \"$ENTITY_ID\"}")

logger -t home-switch "Turn-on request for $ENTITY_ID returned HTTP $RESPONSE"

if [ "$RESPONSE" = "200" ]; then
    exit 0
else
    exit 1
fi
