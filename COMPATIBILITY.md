# Compatibility

This table records combinations exercised by the project. An unlisted device
may work but has not been verified.

| Component | Tested or supported combination | Notes |
|---|---|---|
| Gateway MCU | ESP32-S3 | Requires BLE, Berry, MI32, web server, and sufficient flash |
| Firmware | Project-provided Tasmota32-S3 build | Built by the included workflow |
| Airthings | Wave Plus model 2930 | Up to two paired monitors |
| Airthings transport | BLE GATT | Local operation; no Airthings cloud account required |
| SmartThings | Hub capable of running Edge drivers | Hub and gateway require local LAN reachability |
| SmartThings integration | Edge driver 2.4.0 | One SmartThings device per physical Airthings monitor |
| Matter integration | Tasmota Matter bridge/Aggregator | Creates separate virtual sensor child devices |
| MQTT | Tasmota MQTT | Optional Home Assistant discovery |
| Host workflow | Windows 10/11, PowerShell, Python, Git, Docker Desktop | Used for patch, build, flash, and verification |

## Network requirements

- ESP32 and SmartThings hub must be on the same routable private network.
- Automatic Edge discovery requires multicast DNS for `_airthings._tcp`.
- MQTT requires broker reachability from the ESP32.
- Neither BLE collection nor the local Edge integration requires cloud access
  after installation.

When reporting a new working combination, include exact board, flash size,
Tasmota build, Airthings model/firmware, hub model/firmware, and driver
version.
