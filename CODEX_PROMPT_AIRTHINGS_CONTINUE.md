# Codex continuation task: Airthings 2930 + Tasmota + Matter

Use this directory as the root. Read `airthings_settings.ini` and `airthings2930_README.md` first.

Run `airthings_standalone.cmd all --preserve` for an already commissioned device, or omit `--preserve` only for an intentional fresh/full flash. Inspect logs and modify the Berry driver, patcher, workflow, or Tasmota source as needed. Continue until:

- `MI32` imports successfully.
- `BLE` imports successfully.
- `MtrInfo` is recognized and endpoints 2–8 exist.
- The Airthings environmental and light read succeeds.
- Battery either returns a validated percentage or reports an explicit battery-only error without discarding environmental readings.
- `/airthings` loads and updates fields using JavaScript without a full-page refresh.

Never place Wi-Fi passwords in documentation, logs, ZIP filenames, or source control.

