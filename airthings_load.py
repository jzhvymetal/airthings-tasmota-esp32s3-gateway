#!/usr/bin/env python3
import argparse
import time
from pathlib import Path

import serial


parser = argparse.ArgumentParser(description="Upload the Airthings Berry driver over Tasmota serial")
parser.add_argument("--port", default="COM8")
args = parser.parse_args()
PORT = args.port
ROOT = Path(__file__).resolve().parent


def read_for(ser, seconds):
    end = time.time() + seconds
    chunks = []
    while time.time() < end:
        if ser.in_waiting:
            chunks.append(ser.read(ser.in_waiting).decode("utf-8", errors="replace"))
        else:
            time.sleep(0.05)
    return "".join(chunks)


def command(ser, text, seconds=6):
    ser.write((text + "\r\n").encode())
    ser.flush()
    output = read_for(ser, seconds)
    print(f">>> {text}\n{output}")
    return output


def upload_file(ser, local_path, remote_path):
    data = local_path.read_bytes()
    output = command(ser, f'Br global.__upload=open("/{remote_path}","w"); print("UPLOAD OPEN")', 2)
    if "UPLOAD OPEN" not in output:
        raise SystemExit(f"Failed to open {remote_path} for upload")

    for offset in range(0, len(data), 100):
        chunk = data[offset : offset + 100]
        output = command(ser, f'Br global.__upload.write(bytes("{chunk.hex()}"))', 1.0)
        if '"Br":"nil"' not in output:
            raise SystemExit(f"Upload failed at byte {offset}")

    output = command(
        ser,
        f'Br global.__upload.close(); global.__upload=nil; print("UPLOAD OK {len(data)}")',
        2,
    )
    if f"UPLOAD OK {len(data)}" not in output:
        raise SystemExit(f"Failed to finish {remote_path}")


with serial.Serial(PORT, 115200, timeout=0.1, write_timeout=2) as ser:
    ser.dtr = False
    ser.rts = False
    time.sleep(0.2)
    print(read_for(ser, 8), end="")

    upload_file(ser, ROOT / "airthings2930_tasmota_berry.be", "airthings2930_tasmota_berry.be")

    autoexec = b'tasmota.set_timer(5000, /-> load("airthings2930_tasmota_berry.be"))\n'
    write_cmd = (
        'Br f=open("/autoexec.be","w"); '
        f'f.write(bytes("{autoexec.hex()}")); '
        'f.close(); print("AUTOEXEC OK")'
    )
    if "AUTOEXEC OK" not in command(ser, write_cmd):
        raise SystemExit("Failed to write autoexec.be")

    output = command(
        ser,
        'Br load("airthings2930_tasmota_berry.be"); print("AIRTHINGS LOAD OK")',
        10,
    )
    if "AIRTHINGS LOAD OK" not in output:
        raise SystemExit("Driver did not load successfully")
