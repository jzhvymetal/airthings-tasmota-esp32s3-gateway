# Contributing

Thank you for helping improve the Airthings Tasmota ESP32-S3 Gateway.

## Before opening an issue

1. Search existing issues and the [troubleshooting guide](TROUBLESHOOTING.md).
2. Confirm the problem still occurs with the latest release.
3. Remove Wi-Fi credentials, tokens, device IDs, public IP addresses, and
   private Airthings identifiers from logs.

## Development workflow

1. Fork the repository and create a focused branch.
2. Copy `airthings_settings.example.ini` to the ignored
   `airthings_settings.ini`.
3. Make the smallest change that solves the problem.
4. Run `python scripts/check_repo.py`.
5. If runtime code changed, run `airthings_standalone.cmd deploy` and verify a
   live BLE reading.
6. If Edge code changed, package it with the SmartThings CLI and include
   relevant `logcat` output in the pull request.

Pull requests should explain the problem, the change, testing performed, and
any compatibility or migration impact. Do not commit generated firmware,
private configuration, logs, tokens, or SmartThings hub/device IDs.
