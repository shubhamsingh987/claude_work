#!/bin/bash
# Forgets the home Wi-Fi and all printer queues, then reboots. With no saved Wi-Fi, comitup brings
# the "PrintBox-xxxx" setup hotspot back up. Pass --no-reboot to skip the reboot (used when building).
set -u
logger -t printbox "factory reset"

nmcli -g UUID,TYPE connection show | awk -F: '$2 == "802-11-wireless" { print $1 }' | while read -r uuid; do
    # Only client connections; comitup's own hotspot profile has mode "ap".
    [ "$(nmcli -g 802-11-wireless.mode connection show "$uuid")" = infrastructure ] && nmcli connection delete "$uuid"
done

for p in $(lpstat -e 2>/dev/null); do lpadmin -x "$p"; done

[ "${1:-}" = --no-reboot ] || systemctl reboot
