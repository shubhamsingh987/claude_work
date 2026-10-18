#!/bin/bash
# Weekly backup of the pihole config and state to /mnt/hdd/backups/weekly (keeps the newest 4).
set -u
DEST=/mnt/hdd/backups/weekly
KEEP=4
log() { logger -t weekly-backup "$*"; echo "$(date '+%F %T') $*"; }
mountpoint -q /mnt/hdd || { log "ABORT: /mnt/hdd not mounted"; exit 1; }
mkdir -p "$DEST"
STAMP=$(date +%F)
OUT="$DEST/pihole-$STAMP.tar.gz"
TMP="$OUT.tmp"
dpkg --get-selections > /tmp/pkg-selections.txt 2>/dev/null
log "starting backup -> $OUT"
tar czf "$TMP" --warning=no-file-changed --ignore-failed-read \
  --exclude="*/node_modules" --exclude="*/cache" --exclude="*/Cache" --exclude="*/.npm" \
  -C / etc home/kudo usr/local usr/lib/check_mk_agent boot/firmware/cmdline.txt boot/firmware/config.txt \
  var/lib/asterisk var/lib/tailscale var/lib/homebridge opt/homebridge/start.sh \
  tmp/pkg-selections.txt 2>/dev/null
rc=$?
# tar exit 1 = files changed while reading (benign); 2 = real error
if [ "$rc" -ge 2 ] || [ ! -s "$TMP" ]; then log "FAILED (tar rc=$rc)"; rm -f "$TMP"; exit 1; fi
mv "$TMP" "$OUT"
( cd "$DEST" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
ls -1t "$DEST"/pihole-*.tar.gz 2>/dev/null | tail -n +$((KEEP+1)) | while read -r old; do rm -f "$old" "$old.sha256"; log "pruned $old"; done
log "OK $(du -h "$OUT" | cut -f1) $(basename "$OUT")"
