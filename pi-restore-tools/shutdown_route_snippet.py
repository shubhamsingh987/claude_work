@app.route("/shutdown", methods=["POST"])
def shutdown():
    """Clean Windows shutdown requested by the Pi's phone assistant (shutdown-llm-pc.sh).
    Needs the shared secret in X-Token; the Pi then waits for this server to stop answering and
    only afterwards cuts the smart plug."""
    import hmac
    token_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "llm_shutdown.token")
    try:
        with open(token_file) as f:
            expected = f.read().strip()
    except OSError:
        return jsonify(error="shutdown not configured"), 503
    if not expected or not hmac.compare_digest(request.headers.get("X-Token", ""), expected):
        return jsonify(error="forbidden"), 403
    log.warning("Shutdown requested by the phone assistant; powering off in 15 s")
    subprocess.Popen(["shutdown", "/s", "/t", "15", "/c", "Shutdown requested by the phone assistant"])
    return jsonify(status="shutting down"), 202


