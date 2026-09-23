# Restoring the HAOS Pi 5 (Home Assistant + kiosk touchscreen + UPS HAT)

Hardware: Raspberry Pi 5, boots from NVMe, Waveshare 3.5" resistive touchscreen (ads7846 over SPI)
as a wall kiosk, Waveshare UPS HAT (D) with a 21700 cell. Reached at `homeassistant.local`.
Background and every gotcha in detail: repo-root `CLAUDE.md`, section `pi5-ups-lcd-case/`.

## What's in this folder

| Path | What it is |
|---|---|
| `config/configuration.yaml`, `automations.yaml`, `scripts.yaml`, `scenes.yaml` | Copies of `/config/*.yaml` |
| `config/markets_rest.yaml`, `config/dashboards/markets.yaml` | Markets dashboard: REST price sensors (CoinGecko + Yahoo, no API keys) and its YAML-mode dashboard. Regenerate both with `python gen_markets.py <outdir>` after editing the ticker lists in `gen_markets.py` |
| `config/themes/cyberpunk-2077.yaml` | Theme (from `flejz/hass-cyberpunk-2077-theme`), applied per user profile |
| `host/boot-config.txt` | `/mnt/boot/config.txt` — I2C on, SPI on, ads7846 touch overlay (`xohms=150`) |
| `host/modules-load.d.txt` | `/etc/modules-load.d/i2c-dev.conf` — makes `/dev/i2c-1` exist after every boot |
| `INVENTORY.md` | Versions, add-ons, integrations, HACS repos, custom_components, backups on the Pi |
| `pull_backup.sh` | Re-runs the snapshot (see "Refreshing" below) |

**Not in git, on purpose:** `.storage/` (users, tokens, integration logins, entity registry),
`secrets.yaml`, add-on `options.json` files (kiosk HA login, SSH add-on password), and HA full
backup `.tar` files. Those belong in OneDrive outside this repo (`.gitignore` enforces it).

## Option A (preferred): restore a full HA backup

A full backup brings back everything, including the logins this folder can't hold.

1. Flash **Home Assistant OS** for Raspberry Pi 5 to the NVMe (Raspberry Pi Imager → Other specific
   purpose OS → Home Assistant). Boot, open `http://homeassistant.local:8123`.
2. On the onboarding screen choose **Restore from backup** and upload the newest `.tar` from
   OneDrive (`HA-Backups/`). Wait for it to finish (it restarts on its own).
3. Then still do **"Host-level tweaks"** below. Full backups do **not** include `config.txt` or
   `modules-load.d`, because those live on the OS partitions, not in `/config`.

Which backups exist, their checksums, and how to add new ones: [`BACKUPS.md`](BACKUPS.md).
Latest: **2026-09-23 16:07**, encrypted, copied to OneDrive `HA-Backups/`. You need the backup
**encryption key** from your password manager to restore it. Make a fresh one after big changes.

## Option B: rebuild by hand from this folder

### 1. Install HAOS
Flash HAOS to NVMe as above, do onboarding, create the user **kudo**.
Settings → System → General: set the home location to the actual building (the auto-guessed
location was ~10 km off last time and made every presence check wrong).

### 2. Add-ons (Settings → Add-ons → Add-on store)
- **Advanced SSH & Web Terminal** (community, `a0d7b954_ssh`): Protection mode **OFF**.
  Config: `username: hassio`, `authorized_keys:`
  `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBUJ4tbggJ5QgUZGy9yxw22ESeFeg+auKSSdvDztYrb8 claude-code-haos`
  (public key only; private half is `~/.ssh/id_ed25519_haos` on the Windows PC), `sftp: false`,
  `zsh: true`, `share_sessions: true`, all forwarding `false`, port 22. Set your own strong
  password. Then from the PC `ssh haos` works again.
- **HAOS Kiosk Display** (`2bec5b12_haoskiosk`): enter the kiosk's HA username/password yourself.
  Non-default settings: `cursor_timeout: 0` (always show cursor). Everything else as shipped:
  `ha_url: http://localhost:8123`, `ha_sidebar: none`, `dark_mode: true`, `screen_timeout: 0`,
  `rotate_display: normal`, `map_touch_inputs: true`, `onscreen_keyboard: true`, `zoom_level: 100`,
  `browser_refresh: 600`, `keyboard_layout: us`.
- **Matter Server**, **RPC Shutdown**: defaults.

### 3. Host-level tweaks (needed after Option A too)
Over `ssh haos` (uses the add-on's passwordless `sudo docker`):
```bash
# back up, then write the boot config from this repo
ssh haos "sudo -n docker run --rm -v /mnt/boot:/b alpine cp /b/config.txt /b/config.txt.bak-restore"
ssh haos "sudo -n docker run --rm -i -v /mnt/boot:/b alpine sh -c 'cat > /b/config.txt'" < host/boot-config.txt
# load i2c-dev on every boot (without this the UPS HAT integration fails after reboots)
ssh haos "sudo -n docker run --rm -v /mnt/overlay/etc/modules-load.d:/m alpine sh -c 'echo i2c-dev > /m/i2c-dev.conf'"
```
Then **reboot the Pi** (Settings → System → Hardware → Reboot host). `config.txt` only loads at
boot. Caution: `boot-config.txt` also contains the stock HAOS lines for the OS version it was
taken from (`os_prefix=slot-B/` etc.). On a fresh install, compare it with the new `config.txt` and
copy over **only the custom lines** (`dtparam=i2c_arm=on`, `dtparam=spi=on`, the
`dtoverlay=ads7846,...` line) rather than overwriting blindly.

### 4. HACS + custom repos
Install HACS, then add each repo in `INVENTORY.md` → "HACS repositories installed"
(HACS → ⋮ → Custom repositories, type Integration unless it's a card). Restart HA.

### 5. Config files
```bash
for f in configuration.yaml automations.yaml scripts.yaml scenes.yaml markets_rest.yaml; do
  ssh haos "sudo -n tee /homeassistant/$f >/dev/null" < config/$f
done
ssh haos "sudo -n mkdir -p /homeassistant/themes /homeassistant/dashboards"
ssh haos "sudo -n tee /homeassistant/dashboards/markets.yaml >/dev/null" < config/dashboards/markets.yaml
ssh haos "sudo -n tee /homeassistant/themes/cyberpunk-2077.yaml >/dev/null" < config/themes/cyberpunk-2077.yaml
```
Developer Tools → YAML → **Check configuration**, then **Restart**.
Note `configuration.yaml` has an `ingress: cockpit:` block that points at `pihole`
(`192.168.1.28:9090`). It's harmless if that's unreachable.

### 6. Integrations that need a human (logins, pairing codes)
Do these yourself. They involve accounts or device codes:
- **Alexa Media Player**: Settings → Add integration. Use your **normal browser** (the Amazon login
  opens a popup). Region `amazon.in`, local URL `http://homeassistant.local:8123`.
- **Tuya**: Smart Life app → user code + QR login. AC control uses Smart Life tap-to-run scenes
  `Ac on` / `Ac off` (→ `scene.ac_on` / `scene.ac_off`). Reload Tuya after adding scenes.
- **Qingping Air Monitor Lite**: joins home Wi-Fi from the phone, then HA discovers it as
  **HomeKit Device**. Pair with the 8-digit code on the device. Don't add it back over Bluetooth.
- **Waveshare UPS HAT (D)**: needs step 3 done first. Defaults: bus `1`, MCU `0x2d`, INA219 `0x43`.
- **HA Companion app (iPhone)**: sign in, Location **Always** + Precise, and in the app
  Settings → Companion App → Sensors turn **SSID** on.
- Solis, Google Cast, Matter etc.: re-add from Settings → Devices & Services as they get discovered.

Entity IDs the automations rely on (rename entities to these if they come back different):
`sensor.qingping_air_monitor_lite_humidity`, `sensor.qingping_air_monitor_lite_co2_carbon_dioxide`,
`scene.ac_on`, `scene.ac_off`, `media_player.shubham_s_3rd_echo_dot`, `sensor.shubhams_iphone_ssid`,
`device_tracker.shubhams_iphone`.

### 7. Per-user bits
- Theme: Profile → Theme → `cyberpunk-2077`. **Never** set `frontend: default_theme:` in
  `configuration.yaml`. It's invalid on this HA version and boots straight into recovery mode.
- Overview favorites: UPS `Battery`, Tuya plugs (pencil icon → Personalize → Add favorite).
- iPhone Shortcut: Wi-Fi join `Tripleplay_A236 4th floor` → Home Assistant → Run Script →
  "Welcome back home Shubham".

### 8. Verify
- `ssh haos "ls /dev/i2c-1"` exists, and the UPS HAT integration shows a battery %.
- Qingping humidity updates every few seconds.
- Developer Tools → Actions: `script.welcome_home` → the 3rd Echo Dot speaks.
- Settings → Automations: 3 automations. "Welcome home" is intentionally **off** (the iPhone
  Shortcut replaced it).

## Refreshing this snapshot
After changing anything on the Pi, from the repo root in Git Bash:
```bash
bash haos-pi5/pull_backup.sh
git add haos-pi5 && git commit -m "Refresh HAOS snapshot" && git push
```
The script never pulls secret-bearing files and refuses to finish if it spots a password/token
pattern in its output.
