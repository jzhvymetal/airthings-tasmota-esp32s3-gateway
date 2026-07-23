#!/usr/bin/env python3
"""Standalone patch/build/flash/commission/verify workflow for Airthings 2930."""
from __future__ import annotations
import argparse, configparser, ipaddress, json, os, shutil, subprocess, sys, time, urllib.parse, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VERSION = "2.3.0"

def run(cmd, timeout=None, env=None):
    print("+", subprocess.list2cmdline([str(x) for x in cmd]), flush=True)
    subprocess.run([str(x) for x in cmd], cwd=ROOT, check=True, timeout=timeout, env=env)

def run_helper(*args, timeout=None):
    env = os.environ.copy()
    env["AIRTHINGS_NO_PAUSE"] = "1"
    run(["cmd", "/d", "/c", "airthings_codex_usb_full.cmd", *args], timeout, env)

def serial_command(port, baud, command, wait=6):
    run([sys.executable, "airthings_serial_verify.py", "--port", port, "--baud", str(baud),
         "--boot-wait", "8", "--response-wait", str(wait), "--command", command], wait + 30)

def http_post(url, fields):
    data = urllib.parse.urlencode(fields).encode()
    parsed = urllib.parse.urlsplit(url)
    request = urllib.request.Request(url, data=data,
        headers={"Referer": f"{parsed.scheme}://{parsed.netloc}/"})
    with urllib.request.urlopen(request, timeout=20) as response:
        return response.read().decode(errors="replace")

def http_command(ip, command):
    url = f"http://{ip}/cm?cmnd={urllib.parse.quote(command)}"
    request = urllib.request.Request(url, headers={"Referer": f"http://{ip}/"})
    with urllib.request.urlopen(request, timeout=20) as response:
        body = response.read().decode(errors="replace")
    if response.status != 200 or "Command\":\"Unknown" in body:
        raise RuntimeError(f"HTTP command failed: {command}: {body[:300]}")
    print(f"HTTP COMMAND OK: {command.split(maxsplit=1)[0]}")
    return body

def wait_for_web(ip, timeout=60):
    deadline = time.time() + timeout
    error = None
    while time.time() < deadline:
        try:
            http_command(ip, "Status 0")
            return
        except Exception as exc:
            error = exc
            time.sleep(2)
    raise RuntimeError(f"Device web API did not become ready at {ip}: {error}")

def http_upload(ip, local_path):
    path = Path(local_path)
    data = path.read_bytes()
    boundary = "----AirthingsWorkflowBoundary7MA4YWxk"
    head = (f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="ufsu"; filename="{path.name}"\r\n'
            "Content-Type: application/octet-stream\r\n\r\n").encode()
    body = head + data + f"\r\n--{boundary}--\r\n".encode()
    url = f"http://{ip}/ufsu?fsz={len(data)}"
    request = urllib.request.Request(url, data=body, headers={
        "Content-Type": f"multipart/form-data; boundary={boundary}",
        "Referer": f"http://{ip}/ufsd",
    })
    with urllib.request.urlopen(request, timeout=60) as response:
        result = response.read().decode(errors="replace")
    if response.status != 200 or "Upload failed" in result:
        raise RuntimeError(f"HTTP upload failed for {path.name}: {result[:300]}")
    print(f"HTTP UPLOAD OK: {path.name} ({len(data)} bytes)")

def load_settings(path):
    cfg = configparser.ConfigParser()
    if not cfg.read(path): raise SystemExit(f"Settings file not found: {path}")
    required = {
        "device": ("com_port", "baud", "device_ip", "airthings_mac", "airthings_address_type"),
        "wifi": ("ssid", "password"),
        "build": ("environment", "jobs", "app_offset"),
        "workflow": ("verify_timeout_seconds",),
    }
    missing = [f"[{section}] {key}" for section, keys in required.items() for key in keys
               if section not in cfg or key not in cfg[section]]
    if missing:
        raise SystemExit("Missing required setting(s): " + ", ".join(missing))
    return cfg

def validate_settings(cfg, action):
    errors = []
    port = cfg["device"]["com_port"].strip()
    mac = cfg["device"]["airthings_mac"].strip().replace(":", "").replace("-", "")
    try:
        ipaddress.ip_address(cfg["device"]["device_ip"].strip())
    except ValueError:
        errors.append("[device] device_ip must be a valid IP address")
    if len(mac) != 12 or any(c not in "0123456789abcdefABCDEF" for c in mac):
        errors.append("[device] airthings_mac must contain 12 hexadecimal digits")
    try:
        if cfg.getint("device", "baud") <= 0: errors.append("[device] baud must be positive")
        if cfg.getint("build", "jobs") <= 0: errors.append("[build] jobs must be positive")
        if cfg.getint("device", "airthings_address_type") not in (0, 1):
            errors.append("[device] airthings_address_type must be 0 or 1")
        int(cfg["build"]["app_offset"], 0)
    except ValueError as exc:
        errors.append(f"numeric setting is invalid: {exc}")
    if action in ("commission", "all"):
        if not cfg["wifi"]["ssid"].strip(): errors.append("[wifi] ssid cannot be empty")
        if cfg["wifi"]["password"].strip() == "CHANGE_ME":
            errors.append("replace [wifi] password = CHANGE_ME")
    if action in ("flash", "commission", "verify", "all"):
        try:
            from serial.tools import list_ports
            ports = {item.device.upper() for item in list_ports.comports()}
            if port.upper() not in ports:
                shown = ", ".join(sorted(ports)) or "none"
                errors.append(f"configured port {port} is unavailable (detected: {shown})")
        except ImportError:
            errors.append("pyserial is not installed; run 00_INSTALL_REQUIREMENTS_AND_CODEX.cmd")
    if errors:
        raise SystemExit("Preflight failed:\n- " + "\n- ".join(errors))

def preflight(cfg, action):
    validate_settings(cfg, action)
    needed = {"patch": ("git", "docker", "python"), "build": ("git", "docker", "python"),
              "flash": ("git", "docker", "python"), "commission": ("python",),
              "deploy": ("python",),
              "verify": ("git", "docker", "python"),
              "all": ("git", "docker", "python")}[action]
    missing = [tool for tool in needed if shutil.which(tool) is None]
    if missing:
        raise SystemExit("Preflight failed: missing tool(s): " + ", ".join(missing))
    if "docker" in needed:
        try:
            subprocess.run(["docker", "info"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           check=True, timeout=20)
        except (subprocess.SubprocessError, OSError):
            raise SystemExit("Preflight failed: Docker Desktop is installed but its engine is not ready")
    print(f"PREFLIGHT OK (workflow {VERSION})")

def configure_matter(ip):
    # Use Tasmota's normal Matter bridge/Aggregator presentation so SmartThings
    # creates a separate child device for every virtual sensor endpoint.
    # Omitting the nobridge checkbox explicitly clears the persistent
    # Force Static endpoints setting if an earlier release enabled it.
    mode_body = http_post(f"http://{ip}/matterc", {
        "save": "1", "menable": "on"
    })
    if "Parameter error" in mode_body:
        raise RuntimeError("Matter bridge mode rejected")
    config = {
        "2":{"type":"v_temp","name":"AT_Temp"},
        "3":{"type":"v_humidity","name":"AT_Humidity"},
        "4":{"type":"v_pressure","name":"AT_Pressure"},
        "5":{"type":"v_illuminance","name":"AT_Light"},
        "6":{"type":"v_airquality","name":"AT_AirQuality"},
        "7":{"type":"v_pressure","name":"AT_RadonShort"},
        "8":{"type":"v_pressure","name":"AT_RadonLong"},
        "9":{"type":"v_temp","name":"AT2_Temp"},
        "10":{"type":"v_humidity","name":"AT2_Humidity"},
        "11":{"type":"v_pressure","name":"AT2_Pressure"},
        "12":{"type":"v_illuminance","name":"AT2_Light"},
        "13":{"type":"v_airquality","name":"AT2_AirQuality"},
        "14":{"type":"v_pressure","name":"AT2_RadonShort"},
        "15":{"type":"v_pressure","name":"AT2_RadonLong"},
    }
    body = http_post(f"http://{ip}/matterc", {"config_json": json.dumps(config, separators=(",", ":"))})
    if "Parameter error" in body: raise RuntimeError("Matter configuration rejected")
    print("MATTER CONFIG OK (bridge mode; separate child devices)")

def verify_http(ip, wait):
    checks = (
        ("Br import MI32; return 'MI32 OK'", "MI32 OK"),
        ("Br import BLE; return 'BLE OK'", "BLE OK"),
        ("MtrInfo", '"MtrInfo"'),
        ("Br return global.airthings2930 != nil", '"true"'),
    )
    for command, expected in checks:
        body = http_command(ip, command)
        if expected not in body:
            raise RuntimeError(f"Verification failed; expected {expected!r} in {body[:300]}")
    http_command(ip, "Br global.airthings2930.read_now(); return 'READ STARTED'")
    time.sleep(wait)
    result = http_command(ip,
        "Br return [global.airthings2930.last_read_ok,global.airthings2930.status,"
        "global.airthings2930.light_raw,global.airthings2930.battery,global.airthings2930.last_error]")
    if not ('true' in result.lower() and "Last read OK" in result):
        raise RuntimeError(f"Airthings runtime verification failed: {result}")
    print(f"AIRTHINGS VERIFY OK: {result}")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("action", choices=["preflight","patch","build","flash","commission","deploy","verify","all"], nargs="?", default="all")
    ap.add_argument("--settings", default="airthings_settings.ini")
    ap.add_argument("--preserve", action="store_true", help="flash app partition only; preserve NVS/filesystem")
    ap.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")
    args = ap.parse_args()
    cfg = load_settings(ROOT / args.settings)
    checked_action = "all" if args.action == "preflight" else args.action
    preflight(cfg, checked_action)
    if args.action == "preflight": return
    port, baud = cfg["device"]["com_port"], cfg.getint("device", "baud")
    env, jobs = cfg["build"]["environment"], cfg["build"]["jobs"]
    ip = cfg["device"]["device_ip"].strip()
    mac = cfg["device"]["airthings_mac"].strip().replace(":", "").replace("-", "").upper()
    atype = cfg["device"]["airthings_address_type"]

    # A fresh package has no Tasmota checkout.  Setup must run before patching;
    # previously `all` failed immediately because the patch target did not exist.
    if args.action in ("patch", "all"):
        source = ROOT / "Tasmota" / "platformio.ini"
        if not source.exists():
            run_helper("setup", env, timeout=900)
        run([sys.executable, "airthings_patch.py"])
    if args.action in ("build", "all"): run_helper("build", env, jobs, timeout=1800)
    if args.action in ("flash", "all"):
        if args.preserve:
            image = ROOT / "Tasmota" / ".pio" / "build" / env / "firmware.bin"
            if not image.is_file():
                raise SystemExit(f"Preserve image not found: {image}. Run the build action first.")
            run([sys.executable, "-m", "esptool", "--chip", "esp32s3", "--port", port, "--baud", "921600",
                 "write-flash", cfg["build"]["app_offset"], image], 240)
        else:
            run_helper("flash", port, env, timeout=360)
    if args.action in ("commission", "all"):
        ssid, password = cfg["wifi"]["ssid"], cfg["wifi"]["password"]
        serial_command(port, baud, f"Backlog SSID1 {ssid}; Password1 {password}; SetOption128 1")
        wait_for_web(ip)
        http_upload(ip, ROOT / "airthings2930_tasmota_berry.be")
        http_upload(ip, ROOT / "autoexec.be")
        http_command(ip, 'Br load("airthings2930_tasmota_berry.be"); print("AIRTHINGS LOAD OK")')
        http_command(ip, f"Br global.airthings2930.pair('{mac}',{atype}); print('PAIRED')")
        time.sleep(12)
        configure_matter(ip)
    if args.action == "deploy":
        wait_for_web(ip)
        http_upload(ip, ROOT / "airthings2930_tasmota_berry.be")
        http_upload(ip, ROOT / "autoexec.be")
        http_command(ip, "Restart 1")
        time.sleep(8)
        wait_for_web(ip)
        configure_matter(ip)
        verify_http(ip, cfg.getint("workflow", "verify_timeout_seconds"))
        print(f"FAST DEPLOY OK: http://{ip}/airthings")
    if args.action in ("verify", "all"):
        wait_for_web(ip)
        verify_http(ip, cfg.getint("workflow", "verify_timeout_seconds"))
        configure_matter(ip)
        print(f"WEB: http://{ip}/airthings")

if __name__ == "__main__": main()
