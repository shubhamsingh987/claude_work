#!/bin/bash
# Turns a fresh Raspberry Pi OS Lite (Bookworm) card into a PrintBox. Run once with sudo, while the
# Pi still has internet. After this the box never needs to go online again.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
cd "$(dirname "$0")/files"

apt-get update
# printer-driver-all + hplip = the offline driver collection; ipp-usb = driverless for newer printers.
apt-get install -y cups cups-filters avahi-daemon ipp-usb printer-driver-all hplip \
    python3-gpiozero comitup

hostnamectl set-hostname printbox
sed -i 's/^127\.0\.1\.1.*/127.0.1.1\tprintbox/' /etc/hosts

# Share queues on the LAN (this also makes CUPS advertise them as AirPrint via Avahi), no remote admin.
cupsctl --share-printers --no-remote-admin --no-remote-any
# Let ipp-usb advertise driverless printers to the network, not just to localhost.
sed -i -E 's/^[[:space:]]*interface[[:space:]]*=.*/interface = all/' /etc/ipp-usb/ipp-usb.conf

install -m 755 printbox-autoadd.sh printbox-factory-reset.sh printbox-button.py /usr/local/sbin/
install -m 644 printbox-autoadd.service printbox-button.service /etc/systemd/system/
install -m 644 99-printbox.rules /etc/udev/rules.d/
install -m 644 comitup.conf /etc/comitup.conf

# comitup runs its own DHCP/DNS for the setup hotspot; a system dnsmasq would fight it.
systemctl disable --now dnsmasq 2>/dev/null || true

systemctl daemon-reload
udevadm control --reload
systemctl enable printbox-autoadd.service printbox-button.service comitup.service ipp-usb.service

echo
echo "Done. To ship this box: sudo /usr/local/sbin/printbox-factory-reset.sh"
echo "(forgets this Wi-Fi, so it boots into the PrintBox-xxxx setup hotspot)"
