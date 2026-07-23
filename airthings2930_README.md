# Airthings Wave Plus 2930 on Tasmota ESP32-S3

Workflow version: **2.3.1**

This package builds and commissions a Tasmota ESP32-S3 image with Berry, BLE/MI32, Matter, and the local Airthings Wave Plus driver.

The live page is `http://<device-ip>/airthings`. It includes live values and reading age, stale-data detection, sensor health, next-read countdown, persistent per-device history, CSV export, diagnostics, polling controls, unit selection, calibration, alert thresholds, Home Assistant discovery, friendly names, pairing for up to two devices, and validated configuration backup/restore.

The read-only `http://<device-ip>/airthings_devices` endpoint returns canonical
cached values for every paired monitor without changing the active sensor or
starting a BLE read. It is used by the optional local SmartThings Edge driver.

The Airthings page provides a persistent polling-time setting from 15 to 86400 seconds. The Tasmota main page shows the last-reading timestamp and next-reading countdown and provides **Read Airthings Now** and **Airthings Settings** buttons.

On the first `patch` or `all` run, the workflow now prepares/clones the Tasmota source before applying the BLE patch. This can take several minutes and requires Docker Desktop and Git.

## Reported values

- Temperature, humidity, pressure, CO2, TVOC
- Radon 24-hour and long-term averages
- Airthings ambient-light raw value
- Airthings battery percentage when its optional command response is received
- Reading timestamp, next-read countdown, raw payload, and battery-only errors
- Battery voltage, successful/failed read counters, retry state, connection duration, and BLE RSSI when available

The Wave Plus has no standard BLE Battery Service. Battery comes from Airthings access-control characteristic `b42e2d06-ade7-11e4-89d3-123b93f75cba`: enable notifications, write command `0x6D` with a response, decode the returned millivolts, then convert voltage to percentage. Some device/firmware combinations do not return this optional response; the environmental reading remains valid and battery displays `-`.

## Configure first

Copy `airthings_settings.example.ini` to the ignored private file `airthings_settings.ini`, then edit it:

```ini
[device]
com_port = COM_PORT
device_ip = 192.168.1.100
airthings_mac = 000000000000
airthings_address_type = 0

[wifi]
ssid = CHANGE_ME
password = CHANGE_ME
```

Do not distribute the ZIP after inserting a real Wi-Fi password. Restore `CHANGE_ME` before sharing it.

## Standalone workflow (no Codex)

Prerequisites: Windows, Python with `pyserial` and `esptool`, Docker Desktop, Git, and the ESP32 on the configured COM port.

Check the configuration, required tools, Docker engine, and configured serial port before starting:

```bat
airthings_standalone.cmd preflight
```

Show the workflow version with `python airthings_workflow.py --version`.

Fresh/full installation (erases flash, then restores configuration):

```bat
airthings_standalone.cmd all
```

Continuing an existing installation while preserving NVS and the filesystem:

```bat
airthings_standalone.cmd all --preserve
```

Individual actions:

```bat
airthings_standalone.cmd preflight
airthings_standalone.cmd patch
airthings_standalone.cmd build
airthings_standalone.cmd flash --preserve
airthings_standalone.cmd commission
airthings_standalone.cmd deploy
airthings_standalone.cmd verify
```

`deploy` is the fast development/update path. It uploads only the Berry driver and `autoexec.be`, restarts Tasmota, configures Matter, and performs the full live verification. It does not patch, build, or flash firmware.

## Reliability, history, and adjustments

- A reading becomes stale when no successful sample exists or its age exceeds twice the configured polling interval.
- Failed connections retry automatically after 5, 10, and 20 seconds before normal polling resumes.
- History keeps the latest 288 samples separately for each paired device. It is checkpointed to `/airthings_history.json` every 12 readings to reduce flash wear and restored after restart. At the default five-minute interval this represents 24 hours.
- Each selected device has its own current-value snapshot and charts. Use **Download current device CSV** for spreadsheet-ready canonical readings.
- Calibration offsets are available for temperature (C), humidity (%), pressure (hPa), and CO2 (ppm). Canonical values are adjusted before display and publishing.
- Alert thresholds cover high CO2, VOC, and Radon; low/high humidity; and low battery. Hysteresis prevents rapid alert/clear chatter and a configurable cooldown limits reminder frequency. Alert and clear events publish to `tele/airthings2930/ALERT`.
- Sensor health is scored from reading freshness, consecutive failures, RSSI, and battery, then shown as Healthy, Warning, or Offline.
- The rolling 50-entry diagnostics log records startup/migration, successful reads, failures, alerts, and configuration changes, and can be downloaded as JSON.
- The JSON backup includes devices and names, polling, units, calibration, thresholds, cooldown, MQTT-unit behavior, discovery preference, schema version, and driver version.
- Restore preview parses and validates the schema version, polling range, device count, array consistency, and MAC lengths without modifying settings. Apply restore repeats validation before changing anything.

## MQTT and Home Assistant

Every successful read publishes to both:

- `tele/airthings2930/<MAC>/SENSOR` — stable per-device topic
- `tele/airthings2930/SENSOR` — compatibility topic containing the most recently read device

Home Assistant MQTT discovery is optional and is enabled from the Airthings page. Discovery entities use the per-device topic and identity. MQTT can publish canonical C/hPa/Bq/m3 values or the selected display units. Matter always receives protocol-standard Celsius and hPa.

## Multiple devices

Up to two Wave Plus devices can be paired and assigned friendly names such as Bedroom or Basement. The driver rotates to the next device on each scheduled poll; **Read Now** reads the device currently selected on the web page. Each device maintains separate current state and history and has a separate MQTT topic, Home Assistant identity, and Matter endpoint names. If two sensors need a sample every five minutes, set the polling interval to 150 seconds because scheduled polls alternate between them.

The standalone workflow is non-interactive. The legacy `assume_yes` setting remains for package compatibility; it does not change Windows, Docker, driver, or organization security policy.

## Codex-assisted workflow

After editing the settings file, run:

```bat
airthings_with_codex.cmd
```

The launcher uses:

```text
--ask-for-approval never --sandbox danger-full-access
```

The equivalent `config.toml` values are in `codex_config.example.toml`. These are high-trust settings and may be blocked by managed organization policy. They affect Codex only; they cannot be controlled by `airthings_settings.ini`.

## Matter endpoints

The workflow uses Tasmota's normal Matter **bridge/Aggregator** mode. SmartThings therefore creates a separate child device for each virtual sensor endpoint. This provides the broadest display coverage available with SmartThings' built-in Matter drivers and does not require a custom Edge driver.

After upgrading from version 2.2.0 or 2.2.1, remove the existing gateway from SmartThings, run the `commission` workflow, restart the ESP32-S3 if requested, and commission Matter again. Controllers cache the previous static descriptor, so an existing pairing does not automatically return to separate child devices.

SmartThings' built-in Matter profile currently exposes only the capabilities it recognizes for this mixed static-endpoint node. In observed operation it shows temperature, humidity, and Air Quality, while omitting pressure, illuminance, standalone CO2/TVOC values, and the named Radon carrier endpoints. The gateway still publishes all of those Matter attributes, as confirmed by `MtrInfo`, but adding unsupported tiles requires a custom SmartThings Edge profile.

Commissioning creates these persistent virtual endpoints:

| Endpoint | Name | Type | Airthings value |
|---:|---|---|---|
| 2 | `AT_Temp` | `v_temp` | Temperature |
| 3 | `AT_Humidity` | `v_humidity` | Relative humidity |
| 4 | `AT_Pressure` | `v_pressure` | Atmospheric pressure |
| 5 | `AT_Light` | `v_illuminance` | Raw ambient light |
| 6 | `AT_AirQuality` | `v_airquality` | CO2 and TVOC |
| 7 | `AT_RadonShort` | `v_pressure` | Radon 24h carrier |
| 8 | `AT_RadonLong` | `v_pressure` | Radon long-term carrier |
| 9 | `AT2_Temp` | `v_temp` | Device 2 temperature |
| 10 | `AT2_Humidity` | `v_humidity` | Device 2 relative humidity |
| 11 | `AT2_Pressure` | `v_pressure` | Device 2 atmospheric pressure |
| 12 | `AT2_Light` | `v_illuminance` | Device 2 raw ambient light |
| 13 | `AT2_AirQuality` | `v_airquality` | Device 2 CO2 and TVOC |
| 14 | `AT2_RadonShort` | `v_pressure` | Device 2 Radon 24h carrier |
| 15 | `AT2_RadonLong` | `v_pressure` | Device 2 Radon long-term carrier |

Tasmota currently lacks a native virtual radon update attribute, so endpoints 7 and 8 use clearly named pressure endpoints as numeric carriers. The Airthings battery is not mapped to the ESP32 Matter root power source because that would incorrectly describe the bridge battery.

## Important files

- `airthings_standalone.cmd` — no-Codex entry point
- `github_publish.cmd` — safe Git initialization, commit, and GitHub push helper
- `.gitignore` — excludes private settings, logs, builds, and firmware
- `airthings_settings.example.ini` — sanitized publishable configuration template
- `airthings_with_codex.cmd` — Codex continuation entry point
- `airthings_workflow.py` — workflow implementation
- `airthings_settings.ini` — user/device settings
- `airthings_patch.py` — idempotent Tasmota BLE patch
- `airthings2930_tasmota_berry.be` — runtime driver and web page
- `airthings_load.py` — acknowledged serial filesystem uploader
- `CODEX_PROMPT_AIRTHINGS_CONTINUE.md` — continuation instructions
- `airthings_codex_usb_full.cmd` — Docker build/flash/acceptance helper

## Verification and recovery

The acceptance test checks `MI32`, `BLE`, and `MtrInfo`. Runtime verification performs a real Airthings read and prints light, battery, status, and any battery-only error.

The helper's `flash` action uses a full erase. Prefer `--preserve` for updates. A full erase removes Wi-Fi, Matter endpoints, pairing, and filesystem files; the `all` workflow recreates them from the INI.

If the device is in Wi-Fi Manager mode, it serves `192.168.4.1`. Supply valid Wi-Fi settings and rerun `airthings_standalone.cmd commission`.

Logs are written under `airthings_tasmota_logs`.

## Optional SmartThings LAN Edge driver

The `smartthings-edge` directory provides an alternative to Matter. The Edge
driver runs locally on a SmartThings-compatible hub and reads cached values
from `/airthings_devices` over the LAN. Each physical Airthings monitor is
created as one SmartThings child device containing:

- Temperature, humidity, atmospheric pressure, CO2, TVOC, and illuminance.
- Battery percentage.
- Short-term Radon on the main component.
- Long-term Radon on a separately labelled component of the same device.

All measurements use standard SmartThings production capabilities; no custom
capability namespace, MQTT broker, cloud relay, or Matter commissioning is
required. For a normal installation, open the
[shared Edge-driver invitation](https://bestow-regional.api.smartthings.com/invite/1J2QymxnWw20),
sign in, enroll the intended hub, install the driver under **Available
Drivers**, and use **Scan nearby** in the SmartThings app. The ESP32 advertises
`_airthings._tcp` and the Edge driver verifies `/airthings_devices` before
creating the gateway. The optional IPv4 setting is only a fallback when mDNS
multicast is blocked.

Developers changing the driver source can instead run
`smartthings_edge_install.cmd` and complete the SmartThings CLI sign-in and
hub/channel selection.

## Version history

### 2.4.0 — 2026-07-23

- Added SmartThings gateway and sensor health monitoring with stale-reading offline state.
- Reports Berry and Edge-driver versions in the SmartThings gateway device information.
- Added the shared Edge-driver channel invitation and SmartThings app screenshot.
- Added an MIT license, compatibility matrix, troubleshooting, backup/migration, contribution, and security documentation.
- Added GitHub issue and pull-request templates.
- Added automated GitHub validation and one-command release preparation/publishing.

### 2.3.1 — 2026-07-23

- Added automatic ESP32 gateway discovery using a dedicated `_airthings._tcp` mDNS service.
- Verifies the Airthings API before creating or updating the SmartThings gateway device.
- Retained the manual IPv4 preference only as an optional fallback for networks that block mDNS.
- Fixed SmartThings Radon `NaN` readings by converting canonical Bq/m3 values to the capability's required pCi/L unit.
- Verified the installed hub reports valid short-term and long-term Radon values.

### 2.3.0 — 2026-07-23

- Added an optional local SmartThings LAN Edge driver.
- Groups all measurements belonging to a physical Airthings monitor into one SmartThings child device.
- Uses standard SmartThings capabilities for temperature, humidity, pressure, CO2, TVOC, illuminance, battery, and both Radon periods.
- Added the read-only `/airthings_devices` API for all paired sensors without changing BLE rotation or the web page's active sensor.
- Added `smartthings_edge_install.cmd` to package and install the driver using the official SmartThings CLI.
- Updated the Berry runtime driver to 2.2.0.

### 2.2.2 — 2026-07-23

- Restored Tasmota's standard Matter bridge/Aggregator presentation.
- Explicitly clears the persistent Force Static endpoints setting during Matter configuration.
- Restored separate SmartThings child devices for the virtual temperature, humidity, pressure, illuminance, air-quality, and named Radon carrier endpoints.
- Documented the required removal and recommissioning step for gateways previously paired in static mode.

### 2.2.1 — 2026-07-23

- Added an explicit Matter AirQuality enum to every Air Quality endpoint update instead of relying only on Tasmota's CO2-derived shadow calculation.
- Uses the Matter scale Unknown, Good, Fair, Moderate, Poor, Very Poor, and Extremely Poor derived from CO2 thresholds.
- Documented the capabilities omitted by SmartThings' built-in Matter presentation when no custom Edge driver is used.

### 2.2.0 — 2026-07-23

- Enabled Tasmota Force Static endpoints (non-bridge) during Matter configuration.
- Suppressed the Matter Aggregator/bridge presentation so SmartThings can group the gateway's standard sensor endpoints under one Matter device without a custom Edge driver.
- Retained separate internal endpoints and all existing temperature, humidity, pressure, light, air-quality, and Radon updates.
- Documented the required one-time SmartThings removal and recommissioning step.

### 2.1.1 — 2026-07-23

- Added `github_publish.cmd` to initialize Git, configure the local author, stage and commit safe files, open GitHub repository creation, configure `origin`, and push `main`.
- Added a mandatory safety check that stops publication if the private `airthings_settings.ini` is not ignored or becomes staged.
- Added `.gitignore` rules for private settings, Tasmota downloads, logs, caches, firmware binaries, and runtime history.
- Added a sanitized `airthings_settings.example.ini` for repository users.
- Configured the publisher's default remote as `https://github.com/jzhvymetal/airthings-tasmota-esp32s3-gateway.git`, while retaining an override prompt.

### 2.1.0 — 2026-07-23

- Made the latest 288 history samples persistent across restarts with wear-conscious 12-reading checkpoints.
- Separated current-value snapshots and history charts by paired device.
- Added friendly device names used by the web UI, MQTT payloads, alerts, and Home Assistant discovery.
- Added canonical CSV history export for the selected device.
- Added per-alert state, clear hysteresis, and configurable reminder cooldown.
- Added a 0–100 sensor health score and Healthy/Warning/Offline state based on freshness, BLE failures, RSSI, and battery.
- Added a rolling 50-entry diagnostic event log and JSON download.
- Added driver/schema version and BLE/Berry/Matter compatibility reporting.
- Added automatic saved-configuration migration to schema v3.
- Added protected restore preview and apply-time validation for version, ranges, device count, arrays, and MAC addresses.

### 2.0.0 — 2026-07-23

- Added live reading age and stale-data reporting to the main page, Airthings page, JSON API, and MQTT.
- Added in-memory charts for temperature, humidity, CO2, VOC, and Radon with a 288-sample history API.
- Added battery millivolts, BLE RSSI, read duration, success/failure counters, and consecutive-failure diagnostics.
- Added configurable alert thresholds with MQTT alert publishing.
- Added three-stage 5/10/20-second retry backoff after failed BLE reads.
- Added persistent calibration offsets for temperature, humidity, pressure, and CO2.
- Added optional Home Assistant MQTT discovery and stable per-device state topics.
- Added pairing and scheduled rotation for up to two Airthings devices, plus separate MQTT topics and Matter endpoints.
- Added JSON configuration backup and restore.
- Added `airthings_standalone.cmd deploy` for driver-only uploads, restart, Matter configuration, and live verification without a firmware build or flash.
- Fixed JSON endpoints to close raw responses without Tasmota's HTML footer.

### 1.7.1 — 2026-07-22

- Reduced unit-selector and Save button width to 220 px on desktop while retaining full-width controls on narrow mobile screens.

### 1.7.0 — 2026-07-22

- Added a persistent MQTT publishing choice: canonical C/hPa/Bq/m3 or the selected display units.
- Added explicit `TemperatureUnit`, `PressureUnit`, and selected `RadonUnit` metadata to MQTT output.
- Emits JSON `null` for temporarily unavailable MQTT sensor fields instead of an invalid bare dash.
- Kept Matter values in protocol-mandated 0.01 C and hPa units; Matter controllers localize their own display. Publishing Fahrenheit or inHg directly into Matter attributes would create invalid readings.

### 1.6.0 — 2026-07-22

- Added persistent Radon display selection between Bq/m3 and pCi/L using 37 Bq/m3 per pCi/L.
- Moved temperature, pressure, and Radon selectors into a collapsible **Display units** panel.
- Arranged unit selectors vertically instead of side by side.

### 1.5.0 — 2026-07-21

- Added persistent temperature display selection between Celsius and Fahrenheit.
- Added persistent pressure display selection between hPa and inHg.
- Applied selected units to the Airthings page, live API, and Tasmota main page while preserving canonical Celsius/hPa values for MQTT and Matter integrations.

### 1.4.2 — 2026-07-21

- Changed Airthings battery conversion to match `sensor.airthings_wave`: a clamped linear scale where 2.2 V is 0% and 3.2 V is 100%, rounded to the nearest whole percent.
- Retained the verified Access Control Point notification decoding and voltage byte positions.

### 1.4.1 — 2026-07-21

- Increased the raw-payload text to a readable 14 px monospace font and placed it in a padded, higher-contrast block with safe wrapping on narrow screens.

### 1.4.0 — 2026-07-21

- Redesigned the Airthings page into responsive status, schedule, actions, readings, and pairing cards.
- Aligned polling controls and action buttons using desktop and mobile grid layouts.
- Moved pairing and discovered-device controls into a collapsible advanced section to keep routine controls uncluttered.
- Improved reading-table alignment, raw-payload wrapping, spacing, and responsive behavior on narrow screens.

### 1.3.1 — 2026-07-21

- Made the polling-time input, manual-pair inputs, and action buttons more compact on the Airthings page while leaving Tasmota's main-page controls unchanged.

### 1.3.0 — 2026-07-21

- Added a persistent polling-interval parameter to the Airthings page, with validation from 15 seconds to 24 hours.
- Added last-reading and next-reading timing rows to the Tasmota main page.
- Added **Read Airthings Now** and **Airthings Settings** buttons to the main page.
- Added the active polling interval to the live `/airthings_api` response.

### 1.2.1 — 2026-07-21

- Moved final MI32, BLE, Matter, driver, and live Airthings-read acceptance checks to acknowledged HTTP responses instead of the unreliable post-boot USB console.
- Final verification now fails unless the runtime driver reports a successful real sensor read and includes its status, light, battery, and error fields in the result.

### 1.2.0 — 2026-07-21

- Changed post-Wi-Fi commissioning to use Tasmota's acknowledged HTTP command and `/ufsu` filesystem-upload endpoints because the ESP32-S3 USB console can stop returning command responses after boot.
- Added device web-readiness polling before driver upload.
- Added the required same-device HTTP `Referer` header for installations using Tasmota's default `SetOption128 1` API protection.
- Kept the serial path only for the initial Wi-Fi bootstrap, when the web API is not yet available.

### 1.1.1 — 2026-07-21

- Fixed commissioning on Windows when Tasmota serial output contains Unicode characters that are not representable by the active console code page. Diagnostic output now uses escaped replacements instead of aborting the workflow.
- Verified a clean Tasmota 15.5.0.1 build and full ESP32-S3 factory flash on the configured hardware.

### 1.1.0 — 2026-07-21

- Added `preflight` validation for required settings, IP and MAC formats, numeric values, Wi-Fi credentials, required tools, Docker readiness, and serial-port availability.
- Added the `--version` option and a single workflow version constant.
- Fixed fresh `all` and `patch` runs by preparing Tasmota before applying the BLE source patch.
- Made Python-to-batch helper calls non-interactive so they no longer stop at `pause`.
- Made the Berry uploader resolve its input relative to the package directory.
- Made the standalone launcher use an absolute package-relative workflow path.
- Added required INI-key validation with actionable errors.
- Normalized colon- or dash-separated Airthings MAC addresses before pairing and added a clear error when a preserve-mode image has not been built.
- Refreshed package checksums after the release changes.

### 1.0.0 — Initial package

- Added Tasmota setup, build, flash, Airthings driver upload and pairing, Matter configuration, and serial/web verification.
