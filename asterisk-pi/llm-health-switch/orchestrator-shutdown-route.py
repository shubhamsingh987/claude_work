# ADD THIS TO THE ORCHESTRATOR (the Flask app on the Windows LLM PC, port 5000).
# It gives the Pi a way to ask for a *clean* Windows shutdown. Without it, the Pi's
# shutdown-llm-pc.sh refuses to cut the smart plug (a hard power cut can corrupt files).
#
# 1) Create the shared secret ONCE on the Pi (you run this; the value never goes through an agent):
#      ssh pihole "head -c 24 /dev/urandom | base64 | sudo tee /etc/asterisk/llm_shutdown.token >/dev/null && sudo chmod 600 /etc/asterisk/llm_shutdown.token"
# 2) Show it on the Pi and paste it into a file on the Windows PC (one line, no quotes):
#      ssh pihole "sudo cat /etc/asterisk/llm_shutdown.token"
#      -> save as  C:\voicebot\llm_shutdown.token   (path below; change it if you like)
# 3) Paste the route below into the orchestrator and restart it.

import hmac
import subprocess
from flask import request, abort

TOKEN_FILE = r"C:\voicebot\llm_shutdown.token"


@app.route("/shutdown", methods=["POST"])           # `app` is the orchestrator's existing Flask app
def shutdown():
    with open(TOKEN_FILE) as f:
        expected = f.read().strip()
    if not expected or not hmac.compare_digest(request.headers.get("X-Token", ""), expected):
        abort(403)
    # 15 s grace, then Windows closes apps and powers off. The Pi waits for this server to stop
    # answering, gives Windows 40 more seconds, and only then turns the smart plug off.
    subprocess.Popen(["shutdown", "/s", "/t", "15", "/c", "Shutdown requested by the phone assistant"])
    return "shutting down", 202
