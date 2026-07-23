# Airthings Tasmota ESP32-S3 Gateway — Firmware Commissioning

Release: **v2.4.0**

This archive contains ready-built Tasmota ESP32-S3 firmware plus the current Airthings Wave Plus 2930 Berry driver and commissioning tools.

## Archive contents

- `tasmota32s3-airthings-mi32-matter.factory.bin` — complete image for a new or fully erased ESP32-S3
- `tasmota32s3-airthings-mi32-matter.app.bin` — application-only image for an existing compatible installation
- `airthings2930_tasmota_berry.be` — Airthings BLE driver and web interface
- `autoexec.be` — loads the driver after BLE initialization
- `airthings_settings.example.ini` — sanitized settings template
- `airthings_standalone.cmd` and supporting Python files — commissioning and verification workflow
- `smartthings-edge/` — optional local SmartThings LAN Edge driver
- `smartthings_edge_install.cmd` — packages and installs the Edge driver using the official SmartThings CLI
- `smartthings-edge-v2.4.0.zip` — prebuilt source package for the optional Edge driver
- `RELEASE_SHA256SUMS.txt` — SHA-256 checksums for files in the archive

## Requirements

- Windows 10 or 11
- ESP32-S3 connected over USB
- Airthings Wave Plus model 2930 nearby
- Python 3.10 or newer
- Python packages `esptool` and `pyserial`
- A 2.4 GHz Wi-Fi network reachable by the ESP32-S3

Install the Python requirements:

```powershell
python -m pip install --upgrade esptool pyserial
```

Determine the ESP32-S3 COM port in Windows Device Manager under **Ports (COM & LPT)**.

For an existing installation, first follow
[`BACKUP_AND_MIGRATION.md`](BACKUP_AND_MIGRATION.md). Prefer preserve mode
unless a clean factory recovery is required.

## 1. Create the private settings file

From the extracted release directory:

```powershell
Copy-Item airthings_settings.example.ini airthings_settings.ini
notepad airthings_settings.ini
```

Set at least:

```ini
[device]
com_port = COM8
baud = 115200
device_ip = 192.168.1.100
airthings_mac = 000000000000
airthings_address_type = 0

[wifi]
ssid = YOUR_WIFI_NAME
password = YOUR_WIFI_PASSWORD
```

Replace:

- `COM8` with the actual serial port.
- `device_ip` with the IP the device will receive. A DHCP reservation is recommended.
- `airthings_mac` with the 12 hexadecimal digits of the Wave Plus BLE MAC, without colons or dashes.
- Wi-Fi values with the local 2.4 GHz network credentials.

Keep `airthings_settings.ini` private. Never upload or commit it.

## 2A. Fresh installation

This erases the entire ESP32-S3 and installs the complete factory image.

```powershell
python -m esptool --chip esp32s3 --port COM8 erase-flash
python -m esptool --chip esp32s3 --port COM8 --baud 921600 write-flash 0x0 tasmota32s3-airthings-mi32-matter.factory.bin
```

Replace `COM8` in both commands. If the board is not detected, hold its **BOOT** button while starting the command, release BOOT after communication begins, and press **RESET** afterward.

## 2B. Update an existing compatible installation

This writes only the application partition at `0xE0000` and preserves NVS and the filesystem:

```powershell
python -m esptool --chip esp32s3 --port COM8 --baud 921600 write-flash 0xE0000 tasmota32s3-airthings-mi32-matter.app.bin
```

Use this only when the installed partition layout is compatible with this project. Use the factory procedure for an unknown layout or a different firmware family.

## 3. Commission Wi-Fi, Airthings, and Matter endpoints

After the ESP32-S3 restarts, run:

```bat
airthings_standalone.cmd commission
```

The commissioning workflow:

1. Sends the configured Wi-Fi credentials over serial.
2. Waits for the configured device IP to become available.
3. Uploads the current Berry driver and `autoexec.be`.
4. Pairs the configured Airthings MAC.
5. Creates the Matter virtual endpoints.

If the device remains in Wi-Fi Manager mode, connect to its access point, browse to `http://192.168.4.1`, configure Wi-Fi, update `device_ip` if necessary, and rerun the commission command.

## 4. Verify the gateway

Run:

```bat
airthings_standalone.cmd verify
```

Verification checks BLE/MI32, Berry, Matter, the loaded driver, and a real Airthings sensor read.

Open the dashboard:

```text
http://DEVICE_IP/airthings
```

The first Airthings read can take several seconds. Battery data uses a second optional BLE transaction, so environmental readings can succeed even when the battery response is temporarily unavailable.

## 5. Commission the Matter bridge with a controller

Open the Tasmota main page and select **Configure Matter**. Use the displayed pairing code or QR code in the preferred Matter controller.

The first Airthings device uses Matter endpoints 2–8. A second paired Airthings device uses endpoints 9–15. Radon values use clearly named virtual pressure endpoints because this Tasmota Matter build does not expose a native virtual Radon update attribute.

## 6. Optional SmartThings Edge installation

The Edge driver is an alternative to Matter for SmartThings. It creates one
SmartThings device per physical Airthings monitor and displays temperature,
humidity, pressure, CO2, TVOC, light, battery, short-term Radon, and long-term
Radon together.

Run:

Open the
[shared SmartThings channel invitation](https://bestow-regional.api.smartthings.com/invite/1J2QymxnWw20),
enroll the hub, and install **Airthings ESP32 Gateway** under **Available
Drivers**. Then use **Scan nearby** in the SmartThings app. The ESP32 advertises
`_airthings._tcp` and is discovered automatically. The manual IPv4 preference
is only a fallback for networks that block mDNS.

Driver developers can instead run `smartthings_edge_install.cmd` from the
source repository.

## Fast driver-only updates

After commissioning, update only the Berry driver and web page without flashing firmware:

```bat
airthings_standalone.cmd deploy
```

## Troubleshooting

- **COM port unavailable:** close serial monitors and confirm the port in Device Manager.
- **Device IP unavailable:** confirm the Wi-Fi credentials, DHCP lease, and configured IP.
- **Airthings read fails:** move the gateway closer, verify the MAC and address type, and use **Scan BLE** on the Airthings page.
- **Battery shows unavailable:** wait for another poll; the environmental payload is independent of the optional battery transaction.
- **Matter devices missing:** rerun `airthings_standalone.cmd commission` or `verify` to recreate endpoints, then reopen Configure Matter.

## Integrity verification

From PowerShell:

```powershell
Get-Content RELEASE_SHA256SUMS.txt
Get-FileHash -Algorithm SHA256 *.bin
```

Compare the displayed firmware hashes with the manifest before flashing.

For additional discovery, stale-reading, Radon, duplicate-device, and recovery
help, see [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).
