p = r'C:\Users\singh\claude_work\CLAUDE.md'
s = open(p, newline='', encoding='utf-8').read().replace('\r\n', '\n')

# 1) networking: the .28 problem is resolved
a = s.index("- **The HT813 sends its SIP to `192.168.1.28`**")
b = s.index("- With `eth0` on `192.168.1.x` and `wlan0` on `192.168.0.x`")
s = s[:a] + '''- **The HT813 sends its SIP to `192.168.1.28`** (the old Wi-Fi address). Router leases are *infinite*, so after the move the router
  kept handing the Ethernet port `.33` even to a fresh DHCP request (a stored-lease wipe on the Pi changed nothing). **Resolved
  2026-10-22 ~16:30 by fixing the binding in the router: `eth0` now has `192.168.1.28`** (MAC `b8:27:eb:ca:80:40`) and real calls
  reach Asterisk again (CDR + AGI log confirmed a real call at 16:38 IST). If calls stop arriving, check `ip -4 -br addr show eth0`
  first. The router's client list still showed the old Wi-Fi entry for a while (harmless).
''' + s[b:]

# 2) HT813 hang-up detection finding + CDR gotcha, placed before "### Misc findings"
m = s.index("### Misc findings")
s = s[:m] + '''### HT813 does not report the caller hanging up (found 2026-10-22) — OPEN
Symptom: after the caller hangs up, the home phone keeps ringing (`Dial` runs its full 30 s) and Asterisk keeps the call alive in
the menu. Evidence: CDR shows `Dial ... NO ANSWER` followed by another ~46 s of menu on a call the caller had already ended — no SIP
`BYE` ever arrived. Cause: the HT813's FXO port isn't detecting the line's disconnect signal, and Asterisk-side settings can't fix
it (`rtp_timeout` is 0, and the HT813 keeps sending RTP anyway). Fix is on the HT813 web page `http://192.168.1.24` (admin password
is the user's; I never logged in): FXO port **Disconnect Tone** (must match the Indian line's disconnect/busy tone — the default is
probably another country's), **Enable Current Disconnect**, and/or **Enable Polarity Reversal**, whichever the line really signals.
Offer on the table: record one test call (`MixMonitor`, temporary, deleted afterwards) and measure the tone's frequency/cadence
to give the exact Disconnect Tone string. Not done — needs the user's OK and a test call.
- **CDR gotcha:** `/var/log/asterisk/cdr-csv/Master.csv` timestamps are **UTC** (IST = UTC+5:30); `messages.log`, the AGI log
  (`/tmp/agi_voicebot.log`, `/tmp/agi_pc_voice.log`) and `journalctl` are local IST.

''' + s[m:]

# 3) open items: drop the stale one, add the real ones
old_start = s.index("### Open items\n1. Static `192.168.1.28`")
open_items = s[old_start:]
new_open = '''### Open items
1. HT813 hang-up detection (above) — the phone keeps ringing after the caller hangs up; needs the HT813 Disconnect Tone/current/
   polarity setting (user's admin login) or a recorded test call to measure the tone.
2. Real end-to-end test of voice shutdown (PC off, then plug off) — wired and refusing bad tokens, never actually fired.
3. End-to-end test calls of the full IVR on a real line: first menu (1 ring phone / 2 assistant / 9 menu), 9/0 keys, filler +
   error→menu, PC-off "yes → boots → auto-connect", press 1/3, offline voice "yes" (Vosk has only seen clean TTS clips).
4. Renew the Tuya IoT Core trial when press-1 starts playing three beeps (`journalctl -t tuya-switch`); delete
   `C:\\Users\\singh\\tuya.secret` / `tuya.local` from the PC (the user does this; Claude doesn't hard-delete files).
5. The old SSD has failing blocks — the clone drive is a spare; plan a replacement.
'''
s = s[:old_start] + new_open
open(p, 'w', newline='\n', encoding='utf-8').write(s)
print("CLAUDE.md:", len(s.splitlines()), "lines")
