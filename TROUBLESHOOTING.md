# Troubleshooting

## SmartThings invitation does not show my hub

- Sign in with the Samsung account that owns or administers the location.
- Confirm the hub is online and supports SmartThings Edge drivers.
- If the hub belongs to another account, that account must accept the
  invitation and enroll it.

## Driver is installed but Scan nearby finds nothing

1. Confirm the ESP32 and hub are on the same routable LAN.
2. Open `http://<gateway-ip>/airthings_devices` from a device on that LAN.
3. Confirm the response contains `driver_version` and a `devices` array.
4. Ensure multicast DNS between the hub and ESP32 is not blocked. Guest Wi-Fi,
   client isolation, and many IoT VLAN configurations block it.
5. If mDNS cannot cross the network, enter the gateway's reserved IPv4 address
   in the Edge device settings and scan again.
6. Run SmartThings Edge `logcat` and look for `_airthings._tcp`, HTTP, or JSON
   errors.

## Device is offline or readings are stale

- The Edge refresh interval reads cached values; it does not trigger BLE.
- Set the BLE polling interval on the Airthings web page.
- With two sensors, scheduled reads alternate. A 300-second interval gives
  each sensor a new reading about every 600 seconds.
- Check the gateway dashboard for reading age, RSSI, retries, and the rolling
  diagnostic log.
- Move the ESP32 closer to the Airthings monitor or reduce 2.4 GHz
  interference.

## Radon shows NaN or no value

- Install the latest Edge driver from the shared channel.
- Pull to refresh after the gateway has completed a valid BLE reading.
- The gateway API stores canonical Bq/m3; the Edge driver converts it to the
  pCi/L unit required by SmartThings.
- If the API value itself is missing, inspect Raw Data and perform **Read
  Now** on the Airthings page.

## Duplicate SmartThings devices

1. Remove the duplicate gateway and its child devices in SmartThings.
2. Keep only the latest Edge driver installed on the hub.
3. Scan nearby once and wait for all sensor children to be created.

For Matter duplicates, remove the Matter bridge from SmartThings, run the
`commission` workflow, and commission it again. Controllers cache endpoint
descriptors across firmware changes.

## Gateway address changes

The driver follows mDNS discovery and persists the latest address. For a
network that blocks mDNS, create a DHCP reservation and configure that address
as the fallback in the gateway device settings.

## Clean Edge-driver reinstall

Remove the gateway device, uninstall the driver from the hub's driver list,
reopen the [shared channel invitation](https://bestow-regional.api.smartthings.com/invite/1J2QymxnWw20),
install the current driver, and scan nearby.

## Firmware recovery

See [Backup, upgrade, and recovery](BACKUP_AND_MIGRATION.md). A factory flash
erases Wi-Fi, pairing, Matter credentials, and filesystem data. Prefer
`airthings_standalone.cmd all --preserve` for compatible upgrades.
