#!/bin/bash
# Monitors the CCTV recordings mount for I/O errors / forced-read-only
# remounts and attempts automatic recovery: stop mediamtx + filebrowser
# (both consume this mount -- filebrowser's entire serving root IS
# /mnt/hdd, see its RequiresMountsFor=), unmount, fsck, remount, restart
# both services.
#
# Installed at /usr/local/bin/hdd-watchdog.sh on pihole, run every 5 minutes
# by hdd-watchdog.timer. See README.md in this folder for install steps and
# background on why this exists.

set -u
MOUNT_POINT="/mnt/hdd"
DEVICE="/dev/disk/by-label/cctv"
FSCK_LOG="/var/log/hdd-watchdog-fsck.log"
LOG_TAG="hdd-watchdog"

log() {
    logger -t "$LOG_TAG" "$*"
    echo "$(date '+%F %T') $*"
}

is_healthy() {
    # Unhealthy if the kernel has forced the mount read-only, OR if a
    # lightweight read hangs/fails outright (I/O error case, which doesn't
    # always flip the mount to "ro" immediately).
    local opts
    opts=$(findmnt -no OPTIONS "$MOUNT_POINT" 2>/dev/null) || return 1
    case ",$opts," in
        *,ro,*) return 1 ;;
    esac
    timeout 5 ls "$MOUNT_POINT" >/dev/null 2>&1
}

if is_healthy; then
    exit 0
fi

log "Unhealthy state detected on $MOUNT_POINT — starting recovery"

systemctl stop mediamtx
log "Stopped mediamtx"
systemctl stop filebrowser
log "Stopped filebrowser"

# Give any lingering writers a moment to actually exit, then unmount
# (falling back to a lazy unmount if something still has it open/wedged).
sleep 2
umount "$MOUNT_POINT" 2>/dev/null || umount -l "$MOUNT_POINT" 2>/dev/null
log "Unmounted (or lazily unmounted) $MOUNT_POINT"

if [ ! -e "$DEVICE" ]; then
    log "Device $DEVICE not present — drive appears physically disconnected. Giving up; will retry next run."
    exit 1
fi

e2fsck -y "$DEVICE" >>"$FSCK_LOG" 2>&1
log "e2fsck exit code: $?"

mount "$MOUNT_POINT"
if mountpoint -q "$MOUNT_POINT"; then
    log "Remounted $MOUNT_POINT successfully"
else
    log "Remount FAILED — manual intervention needed"
    exit 1
fi

systemctl start mediamtx
log "Started mediamtx"
systemctl start filebrowser
log "Started filebrowser"
