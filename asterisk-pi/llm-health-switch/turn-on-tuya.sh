#!/bin/bash
# Switches the Tuya / Smart Life plug:  turn-on-tuya.sh [on|off]   (default: on).
# Exit 0 only if the plug accepted the command.
#   1) Tuya cloud API  (creds in /etc/asterisk/tuya.secret, works from any network)
#   2) LAN fallback    (tinytuya; creds in /etc/asterisk/tuya.local; plug found by device ID
#                       on every run, so a changed DHCP address or router doesn't matter)
# Both credential files are created by the USER, never by an agent. See asterisk-pi/SETUP.md.
#
# /etc/asterisk/tuya.secret   endpoint= access_id= access_secret= device_id= [code=switch_1]
# /etc/asterisk/tuya.local    device_id= local_key= [dps=1]
PY=/opt/tinytuya/venv/bin/python3; [ -x "$PY" ] || PY=/usr/bin/python3
exec "$PY" - "$@" <<'PY'
import hashlib, hmac, json, subprocess, sys, time, urllib.request, uuid

ACTION = (sys.argv[1] if len(sys.argv) > 1 else "on").lower()
if ACTION not in ("on", "off"):
    sys.exit(2)
WANT_ON = ACTION == "on"

def log(msg):
    subprocess.run(["logger", "-t", "tuya-switch", msg])

def read_kv(path):
    cfg = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                cfg[k.strip()] = v.strip()
    return cfg

# ---------- 1) cloud ----------
def cloud():
    cfg = read_kv("/etc/asterisk/tuya.secret")
    for k in ("endpoint", "access_id", "access_secret", "device_id"):
        if not cfg.get(k):
            raise RuntimeError("missing %s" % k)
    code = cfg.get("code", "switch_1")

    def call(method, path, body="", token=""):
        t = str(int(time.time() * 1000)); nonce = str(uuid.uuid4())
        sts = "\n".join([method, hashlib.sha256(body.encode()).hexdigest(), "", path])
        sign = hmac.new(cfg["access_secret"].encode(), (cfg["access_id"] + token + t + nonce + sts).encode(),
                        hashlib.sha256).hexdigest().upper()
        h = {"client_id": cfg["access_id"], "sign": sign, "t": t, "nonce": nonce,
             "sign_method": "HMAC-SHA256", "Content-Type": "application/json"}
        if token:
            h["access_token"] = token
        req = urllib.request.Request(cfg["endpoint"] + path, data=body.encode() if body else None,
                                     headers=h, method=method)
        with urllib.request.urlopen(req, timeout=6) as r:
            return json.load(r)

    tok = call("GET", "/v1.0/token?grant_type=1")
    if not tok.get("success"):
        raise RuntimeError("token: code=%s msg=%s" % (tok.get("code"), tok.get("msg")))
    body = json.dumps({"commands": [{"code": code, "value": WANT_ON}]}, separators=(",", ":"))
    res = call("POST", "/v1.0/iot-03/devices/%s/commands" % cfg["device_id"], body, tok["result"]["access_token"])
    if not res.get("success"):
        raise RuntimeError("command: code=%s msg=%s" % (res.get("code"), res.get("msg")))
    return cfg["device_id"]

# ---------- 2) LAN ----------
CACHE = "/var/tmp/tuya-last-ip"

def local():
    import tinytuya
    cfg = read_kv("/etc/asterisk/tuya.local")
    dev_id, key = cfg.get("device_id"), cfg.get("local_key")
    if not dev_id or not key:
        raise RuntimeError("tuya.local needs device_id and local_key")
    dps = int(cfg.get("dps", "1"))

    def try_ip(ip, ver):
        d = tinytuya.OutletDevice(dev_id, ip, key, version=float(ver))
        d.set_socketTimeout(4); d.set_socketRetryLimit(1)
        r = d.turn_on(switch=dps) if WANT_ON else d.turn_off(switch=dps)
        if not r or "Error" in r or "Err" in r:
            raise RuntimeError("LAN reply: %s" % r)
        return ip

    # fast path: last known address
    try:
        ip, ver = open(CACHE).read().split()
        return try_ip(ip, ver)
    except Exception as e:
        log("LAN cached address failed (%s); rediscovering by device ID" % str(e)[:80])
    # dynamic discovery: UDP broadcast scan on every network the Pi is on
    found = tinytuya.find_device(dev_id=dev_id)
    ip, ver = found.get("ip"), found.get("version")
    if not ip:
        raise RuntimeError("plug %s not found on any attached network" % dev_id)
    ok = try_ip(ip, ver or 3.3)
    open(CACHE, "w").write("%s %s" % (ip, ver or 3.3))
    log("LAN rediscovered %s at %s (v%s)" % (dev_id, ip, ver))
    return ok

errors = []
for name, fn in (("cloud", cloud), ("lan", local)):
    try:
        who = fn()
        log("turn-%s via %s -> OK (%s)" % (ACTION, name, who))
        sys.exit(0)
    except SystemExit:
        raise
    except Exception as e:
        errors.append("%s: %s" % (name, e)); log("%s failed: %s" % (name, e))
log("turn-%s FAILED on all routes: %s" % (ACTION, " | ".join(errors)))
sys.exit(1)
PY
