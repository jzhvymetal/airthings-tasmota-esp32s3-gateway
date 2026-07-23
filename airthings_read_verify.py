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
    command(ser, 'Br global.airthings2930.read_now(); print("READ STARTED")')
    print(read_for(ser, 15), end="")
    command(ser, 'Br print("OK",global.airthings2930.last_read_ok); print("STATUS",global.airthings2930.status); print("TEMP",global.airthings2930.temperature); print("HUM",global.airthings2930.humidity); print("PRESS",global.airthings2930.pressure); print("CO2",global.airthings2930.co2); print("VOC",global.airthings2930.voc); print("RAW",global.airthings2930.raw_hex)')
