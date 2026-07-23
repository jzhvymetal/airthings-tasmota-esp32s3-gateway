# Backup, upgrade, and recovery

## Before upgrading

1. Open the Airthings page and use **Export configuration**.
2. Export history CSV/JSON if it must be retained.
3. Save the current `airthings_settings.ini` locally. It is intentionally
   ignored by Git.
4. Record the ESP32 IP address, serial port, paired sensor names, MQTT topic,
   and Matter/SmartThings setup.
5. Verify the downloaded release hashes before flashing.

## Preferred upgrade

For a compatible existing installation:

```bat
airthings_standalone.cmd all --preserve
```

This writes the application partition and retains NVS and filesystem content.
The workflow then uploads the current Berry files, configures integrations, and
performs a live read.

For a Berry/Edge/web-only update:

```bat
airthings_standalone.cmd deploy
```

## Restore configuration

Use **Import configuration** on the Airthings page. Preview and validate the
file before applying it. Recheck units, calibration, alerts, MQTT discovery,
polling, and both paired sensors after migration.

## Factory recovery

Use the factory image only for a new device or when preserve-mode recovery
fails. A factory flash erases Wi-Fi, Airthings pairing, history, MQTT settings,
Matter credentials, and filesystem files. Follow
[RELEASE_COMMISSIONING.md](RELEASE_COMMISSIONING.md), then restore the exported
configuration and recommission Matter or rescan the Edge driver.

## Rollback

Download the earlier tagged release, verify its checksums, and use its
application image with preserve mode when its storage schema is compatible.
If a rollback behaves incorrectly, factory-flash that release and restore a
configuration exported by the same or an older schema version.
