#!/usr/bin/env python3
"""Idempotently patch Tasmota's Berry BLE client for acknowledged writes."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parent
target = root / "Tasmota" / "tasmota" / "tasmota_xsns_sensor" / "xsns_62_esp32_mi.ino"
if not target.exists():
    raise SystemExit(f"Tasmota source not found: {target}")

text = target.read_text(encoding="utf-8")
old_write = "MI32.conCtx->response && !pChr->canWriteNoResponse()"
new_write = "MI32.conCtx->response"
if old_write in text:
    text = text.replace(old_write, new_write, 1)
elif new_write not in text:
    raise SystemExit("Could not locate BLE write-response expression")

old_checks = "if(pChr->canNotify()){"
if old_checks in text:
    text = text.replace(old_checks, "if(pChr->canNotify() || pChr->canIndicate()){", 1)
old_checks = "if(it->canNotify()){"
if old_checks in text:
    text = text.replace(old_checks, "if(it->canNotify() || it->canIndicate()){", 1)

target.write_text(text, encoding="utf-8")
print(f"PATCH OK: {target}")

