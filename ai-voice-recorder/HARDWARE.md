# What to buy

Everything needed to build the recorder as a battery-powered, standalone
device. Five parts, about **₹1,320**.

Prices and stock were checked on **2026-09-01** and both move — reconfirm
before ordering.

| # | Part | Price | Where |
|---|---|---|---|
| 1 | ESP32-WROOM-32 devkit (30 or 38 pin) | ~₹500 | [Amazon: DOIT DEVKIT V1](https://www.amazon.in/ESP32-WROOM-32-Development-ESP-32S-Bluetooth-Arduino/dp/B084KWNMM4) · [Amazon: REES52](https://www.amazon.in/REES52-WROOM-32-Development-Microcontroller/dp/B0BSV7GBV4) |
| 2 | INMP441 I2S MEMS microphone | ₹139 | [Robu](https://robu.in/product/inmp441-mems-high-precision-omnidirectional-microphone-module-i2s/) |
| 3 | 0.96" OLED, I2C, 4-pin (SSD1306) | ₹239 | [Robu](https://robu.in/product/0-96-inch-128x64-ssd1306-iic-interface-4-pin-oled-module-blue-color-screen/) |
| 4 | 1-cell charge + protect + 5 V boost board | ₹112 | [Robu](https://robu.in/product/1-lithium-battery-pack-charge-and-discharge-board/) |
| 5 | 3.7 V 2000 mAh flat LiPo, with PCB | ₹329 | [Robu](https://robu.in/product/nova-604060-2000mah-3-7v-micro-lipo-battery-pack/) |

Robu ships items 2–5 (₹819; free delivery above ₹999, so consider adding a
JST pigtail and some Dupont wire to clear it). Item 1 was out of stock at Robu
when this was written, hence Amazon.

---

## What each part is for

**1. ESP32-WROOM-32** — runs the firmware: reads the mic over I2S and streams
it to the server over Wi-Fi. Any WROOM-32 devkit works. Prefer a **CP2102 or
CH340** USB bridge; both are well supported and the driver is likely already
installed. The 38-pin version breaks out more GPIO but the 30-pin is fine for
this build.

**2. INMP441** — a digital I2S microphone. It outputs 24-bit samples directly,
so there is no analogue noise, no preamp, and no ADC calibration. This is the
single part not worth substituting: an analogue electret module will give
noticeably worse transcription.

**3. OLED** — optional for a first build; the firmware currently reports state
over serial and the on-board LED. Get the **4-pin I2C** version (VCC, GND, SCL,
SDA), not the 7-pin SPI one.

**4. Charge + protect + boost board** — the part that makes it portable. One
module does three jobs: charges the cell over USB, protects it from
over-charge/over-discharge/short, and **boosts the cell's 3.7 V up to a
regulated 5 V at 2 A**. That last one matters — see Power below.

**5. Flat LiPo pouch cell** — 2000 mAh at 3.7 V. Flat rather than cylindrical
so it sits under the board in a case. This one ships with its own protection
PCB and a 2-pin JST lead.

---

## Power: why item 4 and not a TP4056

The obvious choice is a TP4056, and it is wrong on its own. TP4056 outputs the
**raw cell voltage** (3.0–4.2 V). The ESP32's on-board regulator needs ~5 V on
VIN, and Wi-Fi transmit peaks draw ~300–500 mA — feed it 3.7 V and it browns
out mid-recording. This build transmits *continuously* while recording, which
is the worst case for that failure.

The usual fix is TP4056 + a separate MT3608 boost converter. Item 4 replaces
both with one part, so:

```
LiPo (3.7 V) --> [charge + protect + 5 V boost] --> ESP32 VIN (5 V)
                          ^
                          |
                    USB in (charging)
```

The older **134N3P** module does the same job for ~₹19, but it is rated 1 A,
which is thin here, and it was out of stock. If you find one and want to save
₹90, it will work — just don't also hang the OLED and a speaker off it.

---

## Wiring

Mic pins below match `firmware/src/config.h` as shipped, which in turn match
the existing `esp32-espnow-ptt` walkie-talkie board — that hardware runs this
firmware with nothing re-soldered.

| INMP441 | ESP32 | |
|---|---|---|
| VDD | 3V3 | **not** 5V |
| GND | GND | |
| L/R | GND | selects the left I2S slot |
| SCK | GPIO32 | bit clock |
| WS | GPIO25 | word select |
| SD | GPIO33 | data out of mic |

| OLED | ESP32 |
|---|---|
| VCC | 3V3 |
| GND | GND |
| SCL | GPIO22 |
| SDA | GPIO23 |

Plus a momentary button from **GPIO4 to GND** (internal pull-up, no resistor),
and the status LED on **GPIO2** (already on the devkit).

GPIO22/23 for I2C matches what the walkie-talkie firmware uses, so both
firmwares can share one board. On a fresh build the more common 21/22 is fine
— change it in the sketch.

---

## Before you solder

**Charge slowly.** Item 4 can push 2.4 A. At 2000 mAh that is ~1.2C, above the
0.5–1C pouch cells like. **Charge from a 1 A USB supply**, not a fast charger,
unless you confirm the board limits current.

**Cut the JST lead one wire at a time.** The cell arrives with a 2-pin JST
connector and the board has solder pads. Snipping both wires at once shorts a
charged LiPo across the cutters. This is the one step in the build that can
actually hurt you — do it one conductor at a time, and tin the pads first so
each wire is attached quickly.

**Never run the cell without item 4 in circuit.** The cell's own PCB helps,
but the charge board is what enforces the over-discharge cutoff in normal use.

**3V3, never 5V, on the INMP441.** It is a 3.3 V part.

---

## Not included

- **USB cable** for charging (check whether item 4 is Micro-USB or Type-C
  before assuming you have one).
- **Enclosure.** Nothing here is a kit; it is five boards and a cell.
- **JST socket or pigtail** if you would rather not cut the battery lead.
- **Dupont jumper wires** for breadboarding before you commit to solder.

## Not needed

- ~~TP4056 charger~~ — item 4 includes charging.
- ~~Separate BMS board~~ — item 4 is the BMS for a single cell.
- ~~MT3608 or any boost converter~~ — item 4 outputs 5 V directly.
- ~~18650 cell and holder~~ — superseded by the flat pouch cell.
- ~~Amplifier or speaker~~ — this device records; it never plays back.
