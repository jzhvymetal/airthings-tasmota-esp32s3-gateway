# Codex task: Commission Tasmota Airthings MI32 + Matter on ESP32-S3-N16R8

Use the folder containing this file as the root folder. Do not assume `C:\TEMP`.

The root folder contains:

```text
airthings_codex_usb_full.cmd
airthings_serial_verify.py
CODEX_PROMPT_AIRTHINGS.md
```

The helper script will create/use:

```text
<root>\Tasmota
<root>\airthings_tasmota_logs
```

## Goal

For continued work, also read `CODEX_PROMPT_AIRTHINGS_CONTINUE.md`,
`airthings_settings.ini`, and `airthings2930_README.md`. Prefer the packaged
`airthings_standalone.cmd` actions and preserve-flash mode for an existing device.

Build, flash, and verify Tasmota firmware for:

- ESP32-S3-N16R8
- QIO Flash / OPI PSRAM
- Tasmota Berry
- MI32 legacy BLE Berry modules
- Matter
- Airthings BLE GATT support through Berry

## Acceptance tests

After flashing, the Python USB serial verifier must pass these commands:

```text
Br import MI32; print("MI32 OK")
Br import BLE; print("BLE OK")
MtrInfo
```

Expected:

- `MI32 OK`
- `BLE OK`
- `MtrInfo` response that is not `Unknown command`

## Task loop

1. Run the helper script with the provided COM port.
2. Inspect compile and serial logs under `<root>\airthings_tasmota_logs`.
3. Modify `<root>\Tasmota\platformio_tasmota_cenv.ini` or helper scripts if needed.
4. Rebuild, flash, and retest.
5. Stop only when acceptance tests pass or when you can clearly explain the blocking issue.

## Important commands

For full build/flash/test:

```cmd
airthings_codex_usb_full.cmd all COM7
```

For build only:

```cmd
airthings_codex_usb_full.cmd build
```

For MI32-only test build:

```cmd
airthings_codex_usb_full.cmd build tasmota32s3-mi32-test
```

For test only:

```cmd
airthings_codex_usb_full.cmd test COM7
```
