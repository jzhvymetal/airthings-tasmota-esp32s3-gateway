#!/usr/bin/env python3
"""
Airthings/Tasmota USB serial verifier.

This opens the Tasmota USB serial console, waits for boot output, sends commands,
and checks for expected text in the response.
"""

import argparse
import re
import sys
import time
from pathlib import Path

try:
    import serial
except ImportError:
    print("ERROR: pyserial is not installed. Run: python -m pip install pyserial", file=sys.stderr)
    sys.exit(2)


def read_available(ser: serial.Serial, duration: float) -> str:
    end = time.time() + duration
    chunks = []
    while time.time() < end:
        try:
            n = ser.in_waiting
            if n:
                chunks.append(ser.read(n).decode("utf-8", errors="replace"))
            else:
                time.sleep(0.05)
        except serial.SerialException as exc:
            chunks.append(f"\n[SERIAL ERROR while reading: {exc}]\n")
            break
    return "".join(chunks)


def send_command(ser: serial.Serial, command: str, response_wait: float) -> str:
    ser.write((command + "\r\n").encode("utf-8", errors="replace"))
    ser.flush()
    return read_available(ser, response_wait)


def response_payload(response: str, command: str) -> str:
    """Remove the console's command-echo line before checking its response."""
    lines = response.splitlines()
    echo = re.compile(r"\bCMD:\s*" + re.escape(command) + r"\s*$", re.IGNORECASE)
    return "\n".join(line for line in lines if not echo.search(line.strip()))


def main() -> int:
    # Tasmota may emit UTF-8 status glyphs that the Windows cp1252 console
    # cannot represent.  Never let diagnostic output abort commissioning.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="backslashreplace")
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(errors="backslashreplace")
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", required=True, help="Serial port, example COM7")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--boot-wait", type=float, default=20.0)
    parser.add_argument("--response-wait", type=float, default=5.0)
    parser.add_argument("--log", default="")
    parser.add_argument("--command", action="append", default=[], help="Command to send. Repeatable.")
    parser.add_argument("--expect", action="append", default=[], help="Expected text for matching command. Repeatable.")
    args = parser.parse_args()

    if len(args.expect) not in (0, len(args.command)):
        print("ERROR: --expect count must be zero or match --command count.", file=sys.stderr)
        return 2

    log_lines = []

    def log(text: str) -> None:
        print(text, end="")
        log_lines.append(text)

    log(f"Opening {args.port} at {args.baud} baud...\n")

    try:
        with serial.Serial(args.port, args.baud, timeout=0.1, write_timeout=2) as ser:
            ser.dtr = False
            ser.rts = False
            time.sleep(0.2)

            log(f"Waiting {args.boot_wait:.1f}s for boot/console output...\n")
            boot = read_available(ser, args.boot_wait)
            if boot:
                log("----- BOOT/IDLE OUTPUT BEGIN -----\n")
                log(boot)
                if not boot.endswith("\n"):
                    log("\n")
                log("----- BOOT/IDLE OUTPUT END -----\n")
            else:
                log("No boot output captured. Continuing anyway.\n")

            failed = False

            for i, command in enumerate(args.command):
                expected = args.expect[i] if i < len(args.expect) else ""
                log(f"\n>>> {command}\n")
                response = send_command(ser, command, args.response_wait)
                log(response)
                if response and not response.endswith("\n"):
                    log("\n")

                payload = response_payload(response, command)
                invalid = "Unknown command" in payload or '"Command":"Unknown"' in payload

                if invalid:
                    failed = True
                    log("FAIL: Device reported an unknown command.\n")
                elif expected and expected not in payload:
                    failed = True
                    log(f"FAIL: Expected text not found: {expected!r}\n")
                elif expected:
                    log(f"PASS: Found expected text: {expected!r}\n")

            return 1 if failed else 0

    except serial.SerialException as exc:
        log(f"ERROR: Could not open/use serial port {args.port}: {exc}\n")
        return 2
    finally:
        if args.log:
            log_path = Path(args.log)
            log_path.parent.mkdir(parents=True, exist_ok=True)
            log_path.write_text("".join(log_lines), encoding="utf-8", errors="replace")


if __name__ == "__main__":
    raise SystemExit(main())
