#!/usr/bin/env python3
import configparser
import time
import urllib.error
import urllib.request
from pathlib import Path

import serial

ROOT = Path(__file__).resolve().parent
config = configparser.ConfigParser()
if not config.read(ROOT / "airthings_settings.ini"):
    raise SystemExit("airthings_settings.ini not found; copy airthings_settings.example.ini and edit it")
port = config["device"]["com_port"]
baud = config.getint("device", "baud")
device_ip = config["device"]["device_ip"]


def read_for(ser, seconds):
    end = time.time() + seconds
    chunks = []
    while time.time() < end:
        if ser.in_waiting:
            chunks.append(ser.read(ser.in_waiting).decode("utf-8", errors="replace"))
        else:
            time.sleep(0.05)
    return "".join(chunks)


with serial.Serial(port, baud, timeout=0.1, write_timeout=2) as ser:
    ser.dtr = False
    ser.rts = False
    time.sleep(0.2)
    print(read_for(ser, 12), end="")
    try:
        with urllib.request.urlopen(f"http://{device_ip}/airthings", timeout=10) as response:
            body = response.read().decode("utf-8", errors="replace")
            print(f"HTTP {response.status}, {len(body)} bytes")
            print(body[:500])
    except Exception as exc:
        print(f"HTTP ERROR: {exc}")
    print(read_for(ser, 8), end="")
