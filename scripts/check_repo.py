#!/usr/bin/env python3
"""Fast, dependency-light validation for source, docs, profiles, and checksums."""
from __future__ import annotations

import csv
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION_FILES = {
    "workflow": (ROOT / "airthings_workflow.py", r'VERSION = "([^"]+)"'),
    "berry": (ROOT / "airthings2930_tasmota_berry.be", r'DRIVER_VERSION = "([^"]+)"'),
    "edge": (ROOT / "smartthings-edge/src/init.lua", r'EDGE_DRIVER_VERSION = "([^"]+)"'),
    "readme": (ROOT / "README.md", r"Workflow version: \*\*([^*]+)\*\*"),
}


def fail(message: str, errors: list[str]) -> None:
    errors.append(message)


def tracked_files() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files"], cwd=ROOT, check=True, capture_output=True, text=True
    )
    return [line for line in result.stdout.splitlines() if line]


def check_versions(errors: list[str]) -> None:
    found = {}
    for name, (path, pattern) in VERSION_FILES.items():
        match = re.search(pattern, path.read_text(encoding="utf-8"))
        if not match:
            fail(f"{path.name}: version marker not found", errors)
        else:
            found[name] = match.group(1)
    if len(set(found.values())) > 1:
        fail("version mismatch: " + ", ".join(f"{k}={v}" for k, v in found.items()), errors)


def check_json_and_yaml(errors: list[str]) -> None:
    for path in ROOT.rglob("*.json"):
        if ".git" in path.parts or "Tasmota" in path.parts or "release" in path.parts:
            continue
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:
            fail(f"{path.relative_to(ROOT)}: invalid JSON: {exc}", errors)
    try:
        import yaml
    except ImportError:
        fail("PyYAML is required for profile validation: pip install pyyaml", errors)
        return
    for path in list((ROOT / "smartthings-edge").rglob("*.yml")) + list(
        (ROOT / ".github").rglob("*.yml")
    ):
        try:
            yaml.safe_load(path.read_text(encoding="utf-8"))
        except Exception as exc:
            fail(f"{path.relative_to(ROOT)}: invalid YAML: {exc}", errors)


def check_links(errors: list[str]) -> None:
    link_pattern = re.compile(r"!?\[[^\]]*]\(([^)]+)\)")
    for path in ROOT.glob("*.md"):
        text = path.read_text(encoding="utf-8")
        for target in link_pattern.findall(text):
            target = target.strip().split("#", 1)[0]
            if not target or "://" in target or target.startswith("mailto:"):
                continue
            candidate = (path.parent / target).resolve()
            if not candidate.exists():
                fail(f"{path.name}: missing linked file {target}", errors)


def check_safety(files: list[str], errors: list[str]) -> None:
    forbidden = {
        "airthings_settings.ini",
        ".smartthings-invite-input.json",
    }
    for item in files:
        if Path(item).name.lower() in forbidden:
            fail(f"private/generated file is tracked: {item}", errors)
    ignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
    if "airthings_settings.ini" not in ignore:
        fail(".gitignore must exclude airthings_settings.ini", errors)


def check_checksums(errors: list[str]) -> None:
    manifest = ROOT / "SHA256SUMS.csv"
    with manifest.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))
    for row in rows:
        path = ROOT / row["File"]
        if not path.is_file():
            fail(f"checksum target missing: {row['File']}", errors)
            continue
        actual = hashlib.sha256(path.read_bytes()).hexdigest().upper()
        if actual != row["Hash"].upper():
            fail(f"checksum mismatch: {row['File']}", errors)


def main() -> int:
    errors: list[str] = []
    files = tracked_files()
    check_versions(errors)
    check_json_and_yaml(errors)
    check_links(errors)
    check_safety(files, errors)
    check_checksums(errors)
    if errors:
        print("REPOSITORY CHECK FAILED")
        for error in errors:
            print(f"- {error}")
        return 1
    print("REPOSITORY CHECK OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
