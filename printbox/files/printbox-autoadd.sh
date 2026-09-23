#!/bin/bash
# Adds every plugged-in USB printer that doesn't have a CUPS queue yet, picks a driver from the ones
# already on the card (never downloads anything), and shares it so phones see it as AirPrint.
# Run by printbox-autoadd.service at boot and whenever udev sees a printer plugged in.
set -u
log() { logger -t printbox "$*"; echo "$*"; }

sleep 3   # let the printer finish enumerating before the usb backend probes it

for _ in $(seq 1 30); do lpstat -r >/dev/null 2>&1 && break; sleep 1; done

# Printers with an IPP-over-USB interface are handled by ipp-usb, which advertises them itself.
ipp_usb_capable() {
    local serial=$1 dev intf
    [ -n "$serial" ] || return 1
    for dev in /sys/bus/usb/devices/*; do
        [ "$(cat "$dev/serial" 2>/dev/null)" = "$serial" ] || continue
        for intf in "$dev"/*:*; do
            [ "$(cat "$intf/bInterfaceClass" 2>/dev/null)" = 07 ] &&
            [ "$(cat "$intf/bInterfaceProtocol" 2>/dev/null)" = 04 ] && return 0
        done
    done
    return 1
}

existing=$(lpstat -v 2>/dev/null | sed -n 's/^device for [^:]*: //p')

lpinfo -l -v 2>/dev/null | awk '
    /^Device: uri = /           { uri = $4 }
    /^[ \t]*make-and-model = /  { sub(/^[ \t]*make-and-model = /, ""); mm = $0 }
    /^[ \t]*device-id = /       { sub(/^[ \t]*device-id = /, ""); if (uri ~ /^usb:/) print uri "\t" mm "\t" $0 }
' | while IFS=$'\t' read -r uri mm devid; do
    grep -qxF "$uri" <<<"$existing" && continue

    serial=$(sed -n 's/.*[?&]serial=\([^&]*\).*/\1/p' <<<"$uri")
    if ipp_usb_capable "$serial"; then
        log "$mm: IPP-over-USB printer, left to ipp-usb"
        continue
    fi

    # cups-driverd returns matches best-first when given the printer's own device ID.
    driver=$(lpinfo --device-id "$devid" -m 2>/dev/null | head -n1 | cut -d' ' -f1)
    [ -n "$driver" ] || driver=$(lpinfo --make-and-model "$mm" -m 2>/dev/null | head -n1 | cut -d' ' -f1)
    if [ -z "$driver" ]; then
        log "$mm: no driver on this card, printer not supported"
        continue
    fi

    name=$(tr -c 'A-Za-z0-9_-' '_' <<<"$mm" | sed 's/_*$//' | cut -c1-60)
    [ -n "$name" ] || name=Printer
    if lpadmin -p "$name" -E -v "$uri" -m "$driver" -D "$mm" -o printer-is-shared=true; then
        lpstat -d 2>/dev/null | grep -q 'system default destination' || lpadmin -d "$name"
        log "$mm: added as $name using $driver"
    else
        log "$mm: lpadmin failed with driver $driver"
    fi
done
