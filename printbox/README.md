# PrintBox — plug-in AirPrint box for old USB printers

A Pi Zero 2 W that makes any USB printer with a Linux driver show up as AirPrint on
iPhone/Mac and as a network printer on Android. No cloud, no app, no accounts.

**Status: prototype, written 2026-09-23, not yet run on real hardware.**

## What the buyer does
1. Power it on. Phone → Wi-Fi → join `PrintBox-xxxx`. A setup page pops up (captive portal).
2. Pick the home Wi-Fi, type the password. The box joins it and the hotspot disappears.
3. Plug the printer's USB cable in. Within ~10 s it appears in the phone's print menu.

Moved house or new router? When no known Wi-Fi is in range, the setup hotspot comes back on
its own. Hold the button for 10 s to wipe everything.

## How it works
| Piece | Job |
|---|---|
| [comitup](https://github.com/davesteele/comitup) | Setup hotspot + captive portal, falls back to it when Wi-Fi is lost |
| CUPS + Avahi | Print queues, shared on the LAN → advertised as AirPrint |
| `printer-driver-all`, `hplip` | Offline driver collection (Gutenprint, foo2zjs, splix, HP, …) |
| `ipp-usb` | Newer (≈2015+) printers that speak IPP over USB: driverless, no CUPS queue |
| `printbox-autoadd.sh` | On plug-in (udev) and at boot: finds unconfigured USB printers, picks the best-matching installed driver by device ID, adds + shares the queue |
| `printbox-button.py` | Button on GPIO3 ↔ GND (pins 5–6); hold 10 s → `printbox-factory-reset.sh` |

Logs: `journalctl -t printbox`.

## Build a box
1. Flash **Raspberry Pi OS Lite (64-bit, Bookworm)** with Raspberry Pi Imager; set Wi-Fi + SSH there.
2. Copy this folder over and run `sudo bash install.sh`.
3. Test with a printer, then `sudo /usr/local/sbin/printbox-factory-reset.sh` before shipping.

For many units: build one, then clone its SD card image.

## Known gaps / to test
- None of this has run on hardware yet. First things to check: that `comitup` installs from the
  Bookworm repos (if not, use the author's apt repo linked above), and that a printer with both
  IPP-USB and a normal printer interface doesn't end up with two queues.
- Printers with no Linux driver (some cheap Windows-only "GDI" lasers) will never work; they just
  log "not supported". An LED blink for that isn't built yet.
- No read-only filesystem yet — it would also wipe the saved Wi-Fi and queues, so it needs a
  small writable partition for those. Later.
