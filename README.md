# Airthings Tasmota ESP32-S3 Gateway

An ESP32-S3 gateway for the Airthings Wave Plus 2930, built on Tasmota with Berry, BLE/MI32, MQTT, Home Assistant discovery, and Matter.

[![Validate](https://github.com/jzhvymetal/airthings-tasmota-esp32s3-gateway/actions/workflows/validate.yml/badge.svg)](https://github.com/jzhvymetal/airthings-tasmota-esp32s3-gateway/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Screenshots

| Local gateway dashboard | One-device SmartThings Edge presentation |
|---|---|
| <img src="airthings_page_preview.png" alt="Airthings gateway web interface" width="520"> | <img src="SmartThingsApp.jpg" alt="Airthings measurements displayed in SmartThings" width="260"> |

## Features

- Reads temperature, humidity, pressure, CO2, TVOC, Radon, ambient light, and battery data over BLE.
- Responsive local dashboard with Read Now, configurable polling, reading age, stale-data detection, and sensor-health scoring.
- Persistent per-device history charts and CSV export.
- Friendly names and independent state/history for up to two Airthings sensors.
- Configurable units, calibration offsets, alert thresholds, hysteresis, and cooldown.
- Per-device MQTT topics and optional Home Assistant MQTT discovery.
- Separate Matter virtual endpoints for two sensors.
- Optional local SmartThings LAN Edge driver that groups every reading from one physical Airthings monitor into one SmartThings device.
- SmartThings connectivity health, stale-sensor offline state, and installed Berry/Edge version reporting.
- JSON configuration backup, validation preview, restore, and automatic schema migration.
- Rolling diagnostics and automatic BLE retry/backoff.
- Automated Windows patch, build, flash, commission, deploy, and verification workflows.

## Hardware and prerequisites

- ESP32-S3 supported by Tasmota
- Airthings Wave Plus model 2930
- Windows
- Python with `pyserial` and `esptool`
- Git
- Docker Desktop for firmware builds

## Quick start

1. Clone the repository:

   ```powershell
   git clone https://github.com/jzhvymetal/airthings-tasmota-esp32s3-gateway.git
   cd airthings-tasmota-esp32s3-gateway
   ```

2. Create your private settings file:

   ```powershell
   Copy-Item airthings_settings.example.ini airthings_settings.ini
   notepad airthings_settings.ini
   ```

3. Install or verify requirements:

   ```bat
   00_INSTALL_REQUIREMENTS_AND_CODEX.cmd
   ```

4. Validate the configuration:

   ```bat
   airthings_standalone.cmd preflight
   ```

5. Run a fresh installation:

   ```bat
   airthings_standalone.cmd all
   ```

For an existing installation that should retain its settings and filesystem:

```bat
airthings_standalone.cmd all --preserve
```

For a fast Berry driver and web-interface update without rebuilding or flashing firmware:

```bat
airthings_standalone.cmd deploy
```

## Web interface

After commissioning, open:

```text
http://<device-ip>/airthings
```

The device IP, serial port, Wi-Fi credentials, Airthings MAC, build environment, and verification timeout are configured in the ignored `airthings_settings.ini`.

## MQTT

Each successful read is published to:

```text
tele/airthings2930/<MAC>/SENSOR
```

The compatibility topic below contains the most recently read device:

```text
tele/airthings2930/SENSOR
```

Alerts and clear events are published to:

```text
tele/airthings2930/ALERT
```

## Security and repository safety

Never commit `airthings_settings.ini`; it contains local Wi-Fi and device information. The supplied `.gitignore` excludes that file along with firmware builds, logs, downloaded Tasmota sources, caches, and runtime exports.

Use `airthings_settings.example.ini` as the public template. The GitHub publishing helper performs an additional check and stops if the private settings file becomes staged:

```bat
github_publish.cmd
```

## Documentation

- [Complete setup, operation, Matter mapping, recovery, and version history](airthings2930_README.md)
- [Prebuilt firmware commissioning guide](RELEASE_COMMISSIONING.md)
- [Package overview](README_ROOTDIR.md)
- [Publishable settings template](airthings_settings.example.ini)
- [Release checksums](SHA256SUMS.csv)
- [Compatibility matrix](COMPATIBILITY.md)
- [Troubleshooting](TROUBLESHOOTING.md)
- [Backup, upgrade, and recovery](BACKUP_AND_MIGRATION.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

## Current version

Workflow version: **2.4.0**

The Berry runtime driver reports its own version through the local API and MQTT payload.

## SmartThings Edge option

The `smartthings-edge` directory contains a local LAN driver that bypasses
Matter's device-profile limitations. It uses SmartThings' standard temperature,
humidity, pressure, CO2, TVOC, illuminance, battery, and Radon capabilities.

[Install the Airthings ESP32 Gateway Edge driver](https://bestow-regional.api.smartthings.com/invite/1J2QymxnWw20),
sign in with the Samsung account that owns the hub, enroll the hub, select
**Available Drivers**, and install the driver. Then open the SmartThings app,
choose **Add device**, and use **Scan nearby**.

The driver discovers the ESP32 automatically with mDNS; a manual IPv4 setting
remains available only as a fallback. See
[`smartthings-edge/README.md`](smartthings-edge/README.md) for details.

## Automated validation and releases

Every push and pull request validates versions, profiles, documentation links,
checksums, Python syntax, and SmartThings Lua syntax. Maintainers can prepare a
versioned ZIP and firmware assets with:

```bat
release.cmd 2.4.0 "Release summary"
```

Add `--publish` to commit, tag, push, and create the GitHub release after
reviewing the prepared files.

## License

Released under the [MIT License](LICENSE).
