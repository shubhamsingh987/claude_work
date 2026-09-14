#pragma once

// ---------------------------------------------------------------------------
// Wi-Fi  -- fill these in
// ---------------------------------------------------------------------------
#define WIFI_SSID       "homewifi"
#define WIFI_PASSWORD   "home1234"

// ---------------------------------------------------------------------------
// Server (the machine running server/app.py, on the same LAN)
// ---------------------------------------------------------------------------
#define SERVER_HOST     "192.168.0.212"
#define SERVER_PORT     8000
#define INGEST_PATH     "/ingest"

// Identifies this recorder in the web UI / session metadata.
#define DEVICE_ID       "esp32-recorder-01"

// ---------------------------------------------------------------------------
// Pins  (ESP32 WROOM-32 DevKit)
//
// These match the wiring already on the esp32-espnow-ptt walkie-talkie board,
// so that hardware runs this firmware with nothing re-soldered. Its PTT button
// (GPIO4) and status LED (GPIO2) line up as-is too.
//
//   INMP441        ESP32
//   -------        -----
//   VDD    ------> 3V3      (do NOT use 5V)
//   GND    ------> GND
//   L/R    ------> GND      (mic drives the LEFT slot)
//   SCK    ------> GPIO32   (bit clock)
//   WS     ------> GPIO25   (word select / LRCL)
//   SD     ------> GPIO33   (data out of the mic)
//
//   Button: GPIO4 -> button -> GND   (internal pull-up, active low)
//   LED   : GPIO2 (on-board blue LED)
//
// Wiring a mic from scratch instead? Any free pins work; SCK=14, WS=15, SD=32
// is a common choice.
// ---------------------------------------------------------------------------
#define PIN_I2S_SCK     32
#define PIN_I2S_WS      25
#define PIN_I2S_SD      33

#define PIN_BUTTON      4
#define PIN_LED         2

// ---------------------------------------------------------------------------
// Audio
// ---------------------------------------------------------------------------
#define SAMPLE_RATE     16000   // Whisper's native rate -- do not change lightly
#define SAMPLE_BITS     16      // what we put on the wire (PCM s16le, mono)

// The INMP441 is a 24-bit mic delivered in 32-bit slots. We take the top 16
// bits and then apply this digital gain. Aim for an RMS of roughly 1000-4000
// on the serial meter while you talk: measured at 6, normal speech at desk
// distance only reached ~200, which is too quiet for reliable recognition.
// Lower it again if the meter reports clipping.
#define MIC_GAIN        16

// Frames pulled from the I2S DMA per read, and the size of one HTTP chunk.
// 2048 frames @16 kHz = 128 ms = a 4 KB payload. Bigger blocks mean fewer,
// fuller TCP segments, which is what keeps a weak Wi-Fi link at real time.
#define FRAMES_PER_READ 2048

// Safety stop so a forgotten button press cannot record forever.
#define MAX_RECORD_MS   (10 * 60 * 1000UL)

// How long to wait for the server to answer with the transcript after we
// close the audio stream (transcription + summarisation take a few seconds).
#define RESPONSE_TIMEOUT_MS 120000UL

// Button debounce window.
#define DEBOUNCE_MS     50
