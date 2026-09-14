// ---------------------------------------------------------------------------
//  AI voice recorder -- ESP32 WROOM-32 + INMP441 I2S microphone
//
//  Press the button  -> opens an HTTP chunked POST to the notes server and
//                       streams raw 16 kHz mono PCM for as long as you talk.
//  Press it again    -> ends the stream; the server transcribes, separates
//                       speakers and summarises, then returns the notes, which
//                       are printed on the serial monitor.
//
//  Wiring and tunables live in config.h.
// ---------------------------------------------------------------------------
#include <Arduino.h>
#include <Preferences.h>
#include <WiFi.h>

#include "config.h"

#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
  #define USE_I2S_STD_DRIVER 1
  #include <driver/i2s_std.h>
#else
  #define USE_I2S_STD_DRIVER 0
  #include <driver/i2s.h>
#endif

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
enum RecorderState { IDLE, RECORDING };
static RecorderState state = IDLE;

static WiFiClient net;

// Where to send audio. SERVER_HOST in config.h is only the factory default:
// the value actually used is kept in NVS so a DHCP change costs a serial
// command rather than a reflash (this board's auto-reset is unreliable, so
// re-flashing means holding BOOT by hand every time).
static Preferences prefs;
static String   serverHost;
static uint16_t serverPort = SERVER_PORT;

static int32_t rawFrames[FRAMES_PER_READ];   // 32-bit slots straight from I2S

// One HTTP chunk, assembled in place so it leaves as a single write():
//   [ chunk-size header ][ PCM payload ][ CRLF ]
// The header is right-justified to end at HDR_ROOM, so the whole frame is
// contiguous and we never send the header, body and trailer as three tiny
// packets -- doing that collapsed throughput to a third of real time.
#define HDR_ROOM 8                           // "1000\r\n" is 6 bytes, 8 is plenty
static uint8_t  txBuf[HDR_ROOM + FRAMES_PER_READ * 2 + 2];
static int16_t *pcmOut = (int16_t *)(txBuf + HDR_ROOM);

static uint32_t recordStartMs = 0;
static uint32_t bytesSent     = 0;

// Running level meter, so a mis-wired mic is obvious on the serial monitor.
static uint64_t levelSumSq   = 0;
static uint32_t levelSamples = 0;
static uint32_t lastMeterMs  = 0;
static uint32_t clipCount    = 0;

#if USE_I2S_STD_DRIVER
static i2s_chan_handle_t i2sRx = NULL;
#endif

// ---------------------------------------------------------------------------
// LED helpers
// ---------------------------------------------------------------------------
static void ledOn()  { digitalWrite(PIN_LED, HIGH); }
static void ledOff() { digitalWrite(PIN_LED, LOW); }

static void ledBlink(int times, int onMs, int offMs) {
  for (int i = 0; i < times; i++) {
    ledOn();  delay(onMs);
    ledOff(); delay(offMs);
  }
}

// ---------------------------------------------------------------------------
// I2S
// ---------------------------------------------------------------------------
static bool i2sBegin() {
#if USE_I2S_STD_DRIVER
  i2s_chan_config_t chanCfg = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_0, I2S_ROLE_MASTER);
  chanCfg.dma_desc_num  = 8;
  chanCfg.dma_frame_num = 512;
  chanCfg.auto_clear    = false;

  if (i2s_new_channel(&chanCfg, NULL, &i2sRx) != ESP_OK) {
    Serial.println("[i2s] i2s_new_channel failed");
    return false;
  }

  i2s_std_config_t stdCfg = {
    .clk_cfg  = I2S_STD_CLK_DEFAULT_CONFIG(SAMPLE_RATE),
    .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_32BIT,
                                                    I2S_SLOT_MODE_MONO),
    .gpio_cfg = {
      .mclk = I2S_GPIO_UNUSED,
      .bclk = (gpio_num_t)PIN_I2S_SCK,
      .ws   = (gpio_num_t)PIN_I2S_WS,
      .dout = I2S_GPIO_UNUSED,
      .din  = (gpio_num_t)PIN_I2S_SD,
      .invert_flags = { .mclk_inv = false, .bclk_inv = false, .ws_inv = false },
    },
  };
  // L/R tied to GND => the INMP441 drives the left slot only.
  stdCfg.slot_cfg.slot_mask = I2S_STD_SLOT_LEFT;

  if (i2s_channel_init_std_mode(i2sRx, &stdCfg) != ESP_OK) {
    Serial.println("[i2s] init_std_mode failed");
    return false;
  }
  if (i2s_channel_enable(i2sRx) != ESP_OK) {
    Serial.println("[i2s] enable failed");
    return false;
  }
#else
  i2s_config_t cfg = {
    .mode                 = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
    .sample_rate          = SAMPLE_RATE,
    .bits_per_sample      = I2S_BITS_PER_SAMPLE_32BIT,
    .channel_format       = I2S_CHANNEL_FMT_ONLY_LEFT,
    .communication_format = I2S_COMM_FORMAT_STAND_I2S,
    .intr_alloc_flags     = ESP_INTR_FLAG_LEVEL1,
    .dma_buf_count        = 8,
    .dma_buf_len          = 512,
    .use_apll             = false,
    .tx_desc_auto_clear   = false,
    .fixed_mclk           = 0,
  };
  i2s_pin_config_t pins = {
    .bck_io_num   = PIN_I2S_SCK,
    .ws_io_num    = PIN_I2S_WS,
    .data_out_num = I2S_PIN_NO_CHANGE,
    .data_in_num  = PIN_I2S_SD,
  };
  if (i2s_driver_install(I2S_NUM_0, &cfg, 0, NULL) != ESP_OK) return false;
  if (i2s_set_pin(I2S_NUM_0, &pins) != ESP_OK) return false;
#endif
  Serial.printf("[i2s] ready: %d Hz mono, SCK=%d WS=%d SD=%d\n",
                SAMPLE_RATE, PIN_I2S_SCK, PIN_I2S_WS, PIN_I2S_SD);
  return true;
}

// Reads one block of frames and converts 32-bit slots -> gained int16.
// Returns the number of samples placed in pcmOut (0 on timeout/error).
static size_t i2sReadBlock() {
  size_t bytesRead = 0;
#if USE_I2S_STD_DRIVER
  if (i2s_channel_read(i2sRx, rawFrames, sizeof(rawFrames), &bytesRead,
                       pdMS_TO_TICKS(200)) != ESP_OK) {
    return 0;
  }
#else
  if (i2s_read(I2S_NUM_0, rawFrames, sizeof(rawFrames), &bytesRead,
               pdMS_TO_TICKS(200)) != ESP_OK) {
    return 0;
  }
#endif

  const size_t frames = bytesRead / sizeof(int32_t);
  for (size_t i = 0; i < frames; i++) {
    // Top 16 bits of the mic's 24-bit sample, then digital gain.
    int32_t s = (rawFrames[i] >> 16) * MIC_GAIN;
    if (s >  32767) { s =  32767; clipCount++; }
    if (s < -32768) { s = -32768; clipCount++; }
    pcmOut[i] = (int16_t)s;

    levelSumSq += (uint64_t)((int32_t)pcmOut[i] * (int32_t)pcmOut[i]);
    levelSamples++;
  }
  return frames;
}

// Bytes of PCM one second of audio should produce.
#define BYTES_PER_SEC ((uint32_t)SAMPLE_RATE * 2)

// Percentage of the audio we actually got onto the wire. Anything below ~98
// means the link could not keep up and speech was dropped, which otherwise
// shows up only as a recording that is mysteriously shorter than the take.
static uint32_t capturePercent() {
  const uint32_t elapsed = millis() - recordStartMs;
  if (elapsed < 500) return 100;
  const uint64_t expected = (uint64_t)elapsed * BYTES_PER_SEC / 1000;
  return expected ? (uint32_t)((uint64_t)bytesSent * 100 / expected) : 100;
}

static void printMeter() {
  if (levelSamples == 0) return;
  const uint32_t rms = (uint32_t)sqrt((double)levelSumSq / (double)levelSamples);
  const uint32_t pct = capturePercent();

  Serial.printf("[mic] rms=%-6lu sent=%lu KB  realtime=%lu%% %s%s\n",
                (unsigned long)rms, (unsigned long)(bytesSent / 1024),
                (unsigned long)pct,
                pct < 98 ? "<- DROPPING AUDIO, link too slow " : "",
                clipCount ? "(clipping - lower MIC_GAIN)" : "");
  levelSumSq   = 0;
  levelSamples = 0;
  clipCount    = 0;
}

// ---------------------------------------------------------------------------
// Wi-Fi
// ---------------------------------------------------------------------------
static void wifiConnect() {
  if (WiFi.status() == WL_CONNECTED) return;

  Serial.printf("[wifi] connecting to %s", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);              // keeps the audio stream from stuttering
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  uint32_t start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 30000) {
    ledOn();  delay(100);
    ledOff(); delay(400);
    Serial.print(".");
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("[wifi] connected, ip=%s rssi=%d\n",
                  WiFi.localIP().toString().c_str(), WiFi.RSSI());
  } else {
    Serial.println("[wifi] FAILED - check credentials in config.h");
  }
}

// ---------------------------------------------------------------------------
// Streaming upload (HTTP/1.1 chunked POST)
// ---------------------------------------------------------------------------
static bool startRecording() {
  if (WiFi.status() != WL_CONNECTED) {
    wifiConnect();
    if (WiFi.status() != WL_CONNECTED) return false;
  }

  Serial.printf("[net] connecting to %s:%u ...\n", serverHost.c_str(), serverPort);
  if (!net.connect(serverHost.c_str(), serverPort, 5000)) {
    Serial.printf("[net] connect FAILED - is app.py running on %s:%u?\n"
                  "      if the server moved, type:  s <new-ip>\n",
                  serverHost.c_str(), serverPort);
    return false;
  }
  net.setNoDelay(true);

  // Headers describe the raw stream that follows; the body is the PCM itself.
  net.printf("POST %s HTTP/1.1\r\n", INGEST_PATH);
  net.printf("Host: %s:%u\r\n", serverHost.c_str(), serverPort);
  net.print("User-Agent: esp32-voice-recorder/1.0\r\n");
  net.printf("X-Device-Id: %s\r\n", DEVICE_ID);
  net.printf("X-Sample-Rate: %d\r\n", SAMPLE_RATE);
  net.print("X-Channels: 1\r\n");
  net.printf("X-Bits: %d\r\n", SAMPLE_BITS);
  net.print("Content-Type: application/octet-stream\r\n");
  net.print("Transfer-Encoding: chunked\r\n");
  net.print("Connection: close\r\n");
  net.print("\r\n");

  recordStartMs = millis();
  bytesSent     = 0;
  levelSumSq    = 0;
  levelSamples  = 0;
  clipCount     = 0;
  lastMeterMs   = millis();

  state = RECORDING;
  ledOn();
  Serial.println("[rec] RECORDING - press the button again to stop");
  return true;
}

// Emits the PCM already sitting in pcmOut as one HTTP chunk, in one write().
static bool sendChunk(size_t payloadLen) {
  char header[HDR_ROOM + 1];
  const int hlen = snprintf(header, sizeof(header), "%X\r\n", (unsigned)payloadLen);
  if (hlen <= 0 || hlen > HDR_ROOM) return false;

  uint8_t *start = txBuf + HDR_ROOM - hlen;
  memcpy(start, header, hlen);                       // header ends where PCM starts
  txBuf[HDR_ROOM + payloadLen]     = '\r';
  txBuf[HDR_ROOM + payloadLen + 1] = '\n';

  const size_t total = hlen + payloadLen + 2;
  return net.write(start, total) == total;
}

static void pumpAudio() {
  const size_t frames = i2sReadBlock();
  if (frames == 0) return;

  if (!net.connected() || !sendChunk(frames * sizeof(int16_t))) {
    Serial.println("[net] stream broke - aborting recording");
    net.stop();
    state = IDLE;
    ledOff();
    ledBlink(3, 80, 80);
    return;
  }
  bytesSent += frames * sizeof(int16_t);

  if (millis() - lastMeterMs >= 1000) {
    printMeter();
    lastMeterMs = millis();
  }
}

// Ends the chunked body and waits for the server's JSON reply.
static void stopRecording() {
  const uint32_t seconds = (millis() - recordStartMs) / 1000;
  const uint32_t pct     = capturePercent();

  Serial.printf("[rec] stopped after %lus - %lu KB = %.1fs of audio (%lu%% of real time)\n",
                (unsigned long)seconds, (unsigned long)(bytesSent / 1024),
                (double)bytesSent / BYTES_PER_SEC, (unsigned long)pct);
  if (pct < 98) {
    Serial.printf("[rec] WARNING: %lu%% of the audio never made it out. Move the "
                  "board closer to the router (rssi now %d).\n",
                  (unsigned long)(100 - pct), WiFi.RSSI());
  }

  if (net.connected()) {
    net.print("0\r\n\r\n");           // terminating chunk
    net.flush();
  }

  state = IDLE;
  ledOff();

  if (bytesSent == 0) {
    Serial.println("[rec] no audio captured - check the mic wiring");
    net.stop();
    ledBlink(3, 80, 80);
    return;
  }

  Serial.println("[net] waiting for transcript (this takes a few seconds)...");

  const uint32_t deadline = millis() + RESPONSE_TIMEOUT_MS;
  String response;
  while ((int32_t)(millis() - deadline) < 0) {
    while (net.available()) {
      response += (char)net.read();
    }
    if (!net.connected() && !net.available()) break;
    delay(20);
  }
  net.stop();

  if (response.length() == 0) {
    Serial.println("[net] no response from server (timed out)");
    ledBlink(3, 80, 80);
    return;
  }

  const int bodyAt = response.indexOf("\r\n\r\n");
  Serial.println("---------------- server response ----------------");
  Serial.println(bodyAt >= 0 ? response.substring(bodyAt + 4) : response);
  Serial.println("-------------------------------------------------");
  ledBlink(2, 60, 120);
}

// ---------------------------------------------------------------------------
// Button (active low, debounced, toggles recording)
// ---------------------------------------------------------------------------
static bool buttonPressed() {
  static int      lastReading = HIGH;
  static int      stable      = HIGH;
  static uint32_t lastChange  = 0;

  const int reading = digitalRead(PIN_BUTTON);
  if (reading != lastReading) {
    lastReading = reading;
    lastChange  = millis();
  }
  if (millis() - lastChange > DEBOUNCE_MS && reading != stable) {
    stable = reading;
    if (stable == LOW) return true;   // falling edge = press
  }
  return false;
}

static void toggleRecording() {
  if (state == IDLE) {
    if (!startRecording()) ledBlink(3, 80, 80);
  } else {
    stopRecording();
  }
}

// ---------------------------------------------------------------------------
// Serial console
// ---------------------------------------------------------------------------
static void printStatus() {
  Serial.printf("[cfg] server   http://%s:%u%s%s\n",
                serverHost.c_str(), serverPort, INGEST_PATH,
                prefs.isKey("server") ? "  (saved)" : "  (compiled default)");
  Serial.printf("[cfg] wifi     %s  ip=%s  rssi=%d\n",
                WIFI_SSID,
                WiFi.status() == WL_CONNECTED
                    ? WiFi.localIP().toString().c_str() : "(not connected)",
                WiFi.RSSI());
  Serial.printf("[cfg] mic      %d Hz mono  SCK=%d WS=%d SD=%d  gain=%d\n",
                SAMPLE_RATE, PIN_I2S_SCK, PIN_I2S_WS, PIN_I2S_SD, MIC_GAIN);
  Serial.println("[cmd] r = record on/off   s <host[:port]> = set server   "
                 "d = default server   i = this info");
}

static void setServer(String arg) {
  arg.trim();
  if (arg.isEmpty()) { Serial.println("[cfg] usage: s 192.168.0.212[:8000]"); return; }

  uint16_t port = SERVER_PORT;
  const int colon = arg.lastIndexOf(':');
  if (colon > 0) {
    port = (uint16_t)arg.substring(colon + 1).toInt();
    arg  = arg.substring(0, colon);
    if (port == 0) { Serial.println("[cfg] bad port"); return; }
  }

  serverHost = arg;
  serverPort = port;
  prefs.putString("server", serverHost);
  prefs.putUShort("port", serverPort);
  Serial.printf("[cfg] saved: http://%s:%u  (survives reboot)\n",
                serverHost.c_str(), serverPort);
}

static void handleSerial() {
  static String line;
  while (Serial.available()) {
    const char c = Serial.read();
    if (c != '\n' && c != '\r') { line += c; continue; }
    if (line.isEmpty()) continue;

    const char cmd = line[0];
    const String arg = line.substring(1);
    switch (cmd) {
      case 'r': case 'R': toggleRecording(); break;
      case 's': case 'S': setServer(arg);    break;
      case 'i': case 'I': printStatus();     break;
      case 'd': case 'D':
        prefs.remove("server");
        prefs.remove("port");
        serverHost = SERVER_HOST;
        serverPort = SERVER_PORT;
        Serial.printf("[cfg] reverted to compiled default %s:%u\n",
                      serverHost.c_str(), serverPort);
        break;
      default:
        Serial.printf("[cmd] unknown '%c' - try i for help\n", cmd);
    }
    line = "";
  }
}

// ---------------------------------------------------------------------------
// Arduino entry points
// ---------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n=== ESP32 AI voice recorder ===");

  pinMode(PIN_LED, OUTPUT);
  ledOff();
  pinMode(PIN_BUTTON, INPUT_PULLUP);

  // A server address saved over serial wins over the one compiled in.
  prefs.begin("voicerec", false);
  // isKey() first: reading an absent key logs a scary ESP-IDF error line.
  serverHost = prefs.isKey("server") ? prefs.getString("server") : String(SERVER_HOST);
  serverPort = prefs.isKey("port")   ? prefs.getUShort("port")   : SERVER_PORT;

  if (!i2sBegin()) {
    Serial.println("[fatal] I2S init failed");
    while (true) { ledBlink(1, 100, 100); }
  }

  wifiConnect();

  printStatus();
  Serial.printf("Press the button on GPIO%d (or send 'r') to start/stop.\n",
                PIN_BUTTON);
}

void loop() {
  if (buttonPressed()) toggleRecording();
  handleSerial();

  if (state == RECORDING) {
    pumpAudio();
    if (state == RECORDING && millis() - recordStartMs > MAX_RECORD_MS) {
      Serial.println("[rec] max duration reached");
      stopRecording();
    }
  } else {
    static uint32_t lastCheck = 0;
    if (millis() - lastCheck > 10000) {
      lastCheck = millis();
      if (WiFi.status() != WL_CONNECTED) wifiConnect();
    }
    delay(5);
  }
}
