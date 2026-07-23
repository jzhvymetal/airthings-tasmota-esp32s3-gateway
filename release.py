#!/usr/bin/env python3
"""Prepare and optionally publish a versioned GitHub release."""
from __future__ import annotations

import argparse
import csv
import hashlib
import re
import shutil
import subprocess
import sys
import zipfile
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ENVIRONMENT = "tasmota32s3-airthings-mi32-matter"
APP_NAME = f"{ENVIRONMENT}.app.bin"
FACTORY_NAME = f"{ENVIRONMENT}.factory.bin"
VERSION_MARKERS = {
    ROOT / "airthings_workflow.py": (r'VERSION = "[^"]+"', 'VERSION = "{version}"'),
    ROOT / "airthings2930_tasmota_berry.be": (
        r'DRIVER_VERSION = "[^"]+"',
        'DRIVER_VERSION = "{version}"',
    ),
    ROOT / "smartthings-edge/src/init.lua": (
        r'EDGE_DRIVER_VERSION = "[^"]+"',
        'EDGE_DRIVER_VERSION = "{version}"',
    ),
    ROOT / "README.md": (
        r"Workflow version: \*\*[^*]+\*\*",
        "Workflow version: **{version}**",
    ),
    ROOT / "README_ROOTDIR.md": (
        r"Current workflow version: \*\*[^*]+\*\*",
        "Current workflow version: **{version}**",
    ),
    ROOT / "RELEASE_COMMISSIONING.md": (
        r"Release: \*\*v[^*]+\*\*",
        "Release: **v{version}**",
    ),
    ROOT / "COMPATIBILITY.md": (
        r"\| SmartThings integration \| Edge driver [^|]+ \|",
        "| SmartThings integration | Edge driver {version} |",
    ),
}


def run(*command: str, capture: bool = False) -> str:
    result = subprocess.run(
        command, cwd=ROOT, check=True, text=True, capture_output=capture
    )
    return result.stdout.strip() if capture else ""


def replace_version(version: str) -> None:
    for path, (pattern, replacement) in VERSION_MARKERS.items():
        text = path.read_text(encoding="utf-8")
        updated, count = re.subn(pattern, replacement.format(version=version), text, count=1)
        if count != 1:
            raise RuntimeError(f"version marker not found in {path.name}")
        path.write_text(updated, encoding="utf-8", newline="\n")


def add_history(version: str, notes: str) -> None:
    path = ROOT / "airthings2930_README.md"
    text = path.read_text(encoding="utf-8")
    if re.search(rf"^### {re.escape(version)}\b", text, re.MULTILINE):
        return
    marker = "## Version history\n"
    entry = f"\n### {version} — {date.today().isoformat()}\n\n- {notes.strip()}\n"
    if marker not in text:
        raise RuntimeError("version history heading not found")
    path.write_text(text.replace(marker, marker + entry, 1), encoding="utf-8", newline="\n")


def update_manifest() -> None:
    manifest = ROOT / "SHA256SUMS.csv"
    with manifest.open(newline="", encoding="utf-8-sig") as handle:
        names = [row["File"] for row in csv.DictReader(handle)]
    tracked = run(
        "git", "ls-files", "--cached", "--others", "--exclude-standard", capture=True
    ).splitlines()
    for name in tracked:
        if name not in names and (ROOT / name).is_file() and not name.startswith(".github/"):
            names.append(name)
    names = sorted(set(names), key=str.casefold)
    with manifest.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["File", "Hash"])
        for name in names:
            path = ROOT / name
            if path.is_file() and path != manifest:
                writer.writerow([name, hashlib.sha256(path.read_bytes()).hexdigest().upper()])


def copy_firmware(destination: Path, app: Path | None, factory: Path | None) -> None:
    build = ROOT / "Tasmota/.pio/build" / ENVIRONMENT
    app = app or build / "firmware.bin"
    factory = factory or build / "firmware.factory.bin"
    for source, name in ((app, APP_NAME), (factory, FACTORY_NAME)):
        if not source.is_file():
            raise FileNotFoundError(f"firmware image not found: {source}")
        shutil.copy2(source, destination / name)


def package(version: str, app: Path | None, factory: Path | None) -> tuple[Path, Path]:
    output = ROOT / "release" / f"v{version}"
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    copy_firmware(output, app, factory)
    included = [
        "README.md", "RELEASE_COMMISSIONING.md", "LICENSE",
        "airthings2930_README.md", "airthings2930_tasmota_berry.be", "autoexec.be",
        "airthings_settings.example.ini", "airthings_standalone.cmd",
        "airthings_workflow.py", "smartthings_edge_install.cmd",
        "SmartThingsApp.jpg", "airthings_page_preview.png",
        "TROUBLESHOOTING.md", "COMPATIBILITY.md", "BACKUP_AND_MIGRATION.md",
    ]
    for name in included:
        source = ROOT / name
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    shutil.copytree(ROOT / "smartthings-edge", output / "smartthings-edge")
    edge_archive = output / f"smartthings-edge-v{version}.zip"
    with zipfile.ZipFile(edge_archive, "w", zipfile.ZIP_DEFLATED) as bundle:
        for path in sorted((ROOT / "smartthings-edge").rglob("*")):
            if path.is_file() and path.name != "README.md" and path.suffix != ".json":
                bundle.write(path, path.relative_to(ROOT / "smartthings-edge").as_posix())
    checksums = output / "RELEASE_SHA256SUMS.txt"
    lines = []
    for path in sorted(output.rglob("*")):
        if path.is_file() and path != checksums:
            digest = hashlib.sha256(path.read_bytes()).hexdigest().upper()
            lines.append(f"{digest}  {path.relative_to(output).as_posix()}")
    checksums.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    archive = ROOT / "release" / f"airthings-tasmota-esp32s3-gateway-v{version}.zip"
    if archive.exists():
        archive.unlink()
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as bundle:
        for path in sorted(output.rglob("*")):
            if path.is_file():
                bundle.write(path, path.relative_to(output).as_posix())
    return output, archive


def publish(version: str, notes: str, output: Path, archive: Path) -> None:
    if run("git", "status", "--porcelain", capture=True):
        run("git", "add", "-A")
        run("git", "commit", "-m", f"Release v{version}")
    run("git", "push", "origin", "main")
    tag = f"v{version}"
    if not run("git", "tag", "--list", tag, capture=True):
        run("git", "tag", "-a", tag, "-m", f"Release {tag}")
        run("git", "push", "origin", tag)
    assets = [
        str(archive),
        str(output / APP_NAME),
        str(output / FACTORY_NAME),
        str(output / "RELEASE_COMMISSIONING.md"),
        str(output / "RELEASE_SHA256SUMS.txt"),
        str(output / "SmartThingsApp.jpg"),
        str(output / f"smartthings-edge-v{version}.zip"),
    ]
    run(
        "gh", "release", "create", tag, *assets, "--title", tag,
        "--notes", notes, "--verify-tag",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("version", help="semantic version, for example 2.4.0")
    parser.add_argument("--notes", required=True, help="release summary")
    parser.add_argument("--app-bin", type=Path)
    parser.add_argument("--factory-bin", type=Path)
    parser.add_argument("--publish", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        parser.error("version must use MAJOR.MINOR.PATCH")
    replace_version(args.version)
    add_history(args.version, args.notes)
    update_manifest()
    output, archive = package(args.version, args.app_bin, args.factory_bin)
    run(sys.executable, "scripts/check_repo.py")
    print(f"Prepared {archive}")
    if args.publish:
        publish(args.version, args.notes, output, archive)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
