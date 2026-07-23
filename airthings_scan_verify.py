#!/usr/bin/env python3
import time

import serial


def read_for(ser, seconds):
    end = time.time() + seconds
    chunks = []
    while time.time() < end:
        if ser.in_waiting:
            chunks.append(ser.read(ser.in_waiting).decode("utf-8", errors="replace"))
        else:
            time.sleep(0.05)
    return "".join(chunks)


def command(ser, text, seconds=3):
    ser.write((text + "\r\n").encode())
    ser.flush()
    output = read_for(ser, seconds)
    print(f">>> {text}\n{output}")
    return output


with serial.Serial("COM8", 115200, timeout=0.1, write_timeout=2) as ser:
    ser.dtr = False
    ser.rts = False
    time.sleep(0.2)
    print(read_for(ser, 12), end="")
    command(ser, 'Br global.airthings2930.start_scan(20); print("SCAN STARTED")')
    print(read_for(ser, 22), end="")
    command(ser, 'Br print("MACS",global.airthings2930.dev_macs); print("TYPES",global.airthings2930.dev_types); print("RSSI",global.airthings2930.dev_rssi); print("SERIALS",global.airthings2930.dev_serials)')
