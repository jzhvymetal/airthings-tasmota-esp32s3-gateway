# Airthings commissioning package

Current workflow version: **2.4.0**

This package is relocatable: every script uses its own directory as the root. Start with `airthings2930_README.md`.

1. Run `00_INSTALL_REQUIREMENTS_AND_CODEX.cmd` once to install/check prerequisites.
2. If needed, copy `airthings_settings.example.ini` to `airthings_settings.ini`, then edit the COM port, Wi-Fi credentials, IP, and Airthings MAC.
3. Run `airthings_standalone.cmd preflight` and correct every reported problem.
4. Without Codex, run `airthings_standalone.cmd all` for a fresh install, `airthings_standalone.cmd all --preserve` for a firmware update, or `airthings_standalone.cmd deploy` for a fast driver/web-page-only update.
5. With Codex, run `airthings_with_codex.cmd` (the legacy `01_RUN_CODEX_AIRTHINGS.cmd` redirects there).
6. To publish or update a GitHub repository safely, run `github_publish.cmd`.

Version 2.4 adds SmartThings health/version reporting, shared driver
installation, public-project safeguards, repository validation, and automated
release packaging.

For details, recovery, Matter mappings, battery behavior, and no-prompt Codex options, see `airthings2930_README.md`.

Also see `COMPATIBILITY.md`, `TROUBLESHOOTING.md`, and
`BACKUP_AND_MIGRATION.md` before deploying to a new board or hub.

For the optional local SmartThings integration, run
`smartthings_edge_install.cmd` and see `smartthings-edge/README.md`.
