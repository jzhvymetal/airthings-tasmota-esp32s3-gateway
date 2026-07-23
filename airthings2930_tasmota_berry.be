# -----------------------------------------------------------------------------
# airthings2930_tasmota_berry.be
# Best-effort Tasmota32 Berry driver for Airthings Wave Plus 2930.
#
# Features:
# - Custom Tasmota web page at /airthings
# - BLE advertisement scan and simple pairing by MAC/address type
# - Reads Wave Plus GATT characteristic b42e2a68-ade7-11e4-89d3-123b93f75cba
# - Displays values on the Tasmota main page and custom page
# - Publishes values in Tasmota SENSOR JSON via json_append()
# - Sends basic Matter virtual updates with MtrUpdate where Tasmota supports them
#
# Notes:
# - Requires ESP32 Tasmota build with Berry + BLE. Matter requires a Tasmota32
#   build with Matter enabled.
# - Radon is published in Bq/m3. Tasmota Matter does not currently expose radon
#   as a first-class MtrUpdate attribute, so RadonShort and RadonLong can be sent
#   as fake Pressure endpoints named AT_RadonShort and AT_RadonLong.
# - CO2/TVOC are included in SENSOR JSON. For Matter, map them through Tasmota
#   Configure Matter if your build/hub exposes the Air Quality plugin correctly.
# -----------------------------------------------------------------------------

import BLE
import webserver
import string
import persist
import json

class Airthings2930 : Driver
  static DRIVER_VERSION = "2.2.0"
  static CONFIG_VERSION = 3
  static SVC_UUID = "b42e1c08-ade7-11e4-89d3-123b93f75cba"
  static DATA_UUID = "b42e2a68-ade7-11e4-89d3-123b93f75cba"
  static BATTERY_UUID = "b42e2d06-ade7-11e4-89d3-123b93f75cba"

  var abuf, cbuf
  var adv_cbp, conn_cbp
  var dev_macs, dev_types, dev_rssi, dev_serials
  var scan_active, scan_left
  var mac_hex, addr_type, paired
  var paired_macs, paired_types, active_index
  var paired_names, device_states, histories
  var poll_seconds, poll_count
  var temp_unit, pressure_unit, radon_unit, mqtt_display_units
  var discovery_enabled, discovery_sent
  var status, last_read_ok, last_error, raw_hex, read_active
  var last_read_epoch, last_read_text
  var version, humidity, radon_short, radon_long, temperature, pressure, co2, voc, light_raw, battery
  var battery_mv, seconds_since_read, uptime_seconds, read_started_second, last_read_duration, last_rssi
  var read_successes, read_failures, consecutive_failures, retry_count, retry_wait
  var cal_temp, cal_humidity, cal_pressure, cal_co2
  var alert_co2, alert_voc, alert_radon, alert_humidity_low, alert_humidity_high, alert_battery
  var history_time, history_temp, history_humidity, history_co2, history_voc, history_radon
  var history_dirty, diagnostic_log, alert_states, alert_last, alert_cooldown
  var migration_status, compatibility_status
  var read_stage

  def init()
    self.abuf = bytes(-96)
    self.cbuf = bytes(-64)

    self.dev_macs = []
    self.dev_types = []
    self.dev_rssi = []
    self.dev_serials = []

    self.scan_active = false
    self.scan_left = 0

    self.paired_macs = json.load(persist.find("air2930_devices", "[]"))
    self.paired_types = json.load(persist.find("air2930_device_types", "[]"))
    self.paired_names = json.load(persist.find("air2930_device_names", "[]"))
    if self.paired_macs == nil self.paired_macs = [] end
    if self.paired_types == nil self.paired_types = [] end
    if self.paired_names == nil self.paired_names = [] end
    var legacy_mac = persist.find("air2930_mac", "")
    if size(self.paired_macs) == 0 && size(legacy_mac) == 12
      self.paired_macs.push(legacy_mac); self.paired_types.push(int(persist.find("air2930_type", "0")))
    end
    while size(self.paired_names) < size(self.paired_macs)
      self.paired_names.push("Airthings " + str(size(self.paired_names) + 1))
    end
    self.active_index = 0
    self.mac_hex = size(self.paired_macs) > 0 ? self.paired_macs[0] : ""
    self.addr_type = size(self.paired_types) > 0 ? self.paired_types[0] : 0
    self.paired = size(self.mac_hex) == 12

    self.poll_seconds = int(persist.find("air2930_poll", "300"))
    if self.poll_seconds < 15 self.poll_seconds = 15 end
    if self.poll_seconds > 86400 self.poll_seconds = 86400 end
    self.poll_count = 10         # do first read shortly after boot
    self.temp_unit = persist.find("air2930_temp_unit", "C")
    if self.temp_unit != "F" self.temp_unit = "C" end
    self.pressure_unit = persist.find("air2930_pressure_unit", "hPa")
    if self.pressure_unit != "inHg" self.pressure_unit = "hPa" end
    self.radon_unit = persist.find("air2930_radon_unit", "Bq/m3")
    if self.radon_unit != "pCi/L" self.radon_unit = "Bq/m3" end
    self.mqtt_display_units = persist.find("air2930_mqtt_units", "0") == "1"
    self.discovery_enabled = persist.find("air2930_discovery", "0") == "1"
    self.discovery_sent = false
    self.cal_temp = real(persist.find("air2930_cal_temp", "0"))
    self.cal_humidity = real(persist.find("air2930_cal_humidity", "0"))
    self.cal_pressure = real(persist.find("air2930_cal_pressure", "0"))
    self.cal_co2 = int(persist.find("air2930_cal_co2", "0"))
    self.alert_co2 = int(persist.find("air2930_alert_co2", "1000"))
    self.alert_voc = int(persist.find("air2930_alert_voc", "250"))
    self.alert_radon = int(persist.find("air2930_alert_radon", "100"))
    self.alert_humidity_low = int(persist.find("air2930_alert_hum_low", "30"))
    self.alert_humidity_high = int(persist.find("air2930_alert_hum_high", "60"))
    self.alert_battery = int(persist.find("air2930_alert_battery", "20"))
    self.alert_cooldown = int(persist.find("air2930_alert_cooldown", "3600"))
    if self.alert_cooldown < 60 self.alert_cooldown = 60 end
    self.migration_status = self.migrate_config()
    self.compatibility_status = "Berry and BLE loaded; Matter endpoints managed by workflow"

    self.status = "Not paired"
    if self.paired
      self.status = "Paired to " + self.mac_hex
    end

    self.last_read_ok = false
    self.last_error = ""
    self.raw_hex = ""
    self.read_active = false
    self.last_read_epoch = nil
    self.last_read_text = "Never"

    self.version = nil
    self.humidity = nil
    self.radon_short = nil
    self.radon_long = nil
    self.temperature = nil
    self.pressure = nil
    self.co2 = nil
    self.voc = nil
    self.light_raw = nil
    self.battery = nil
    self.battery_mv = nil
    self.seconds_since_read = -1
    self.uptime_seconds = 0
    self.read_started_second = 0
    self.last_read_duration = 0
    self.last_rssi = nil
    self.read_successes = 0
    self.read_failures = 0
    self.consecutive_failures = 0
    self.retry_count = 0
    self.retry_wait = 0
    self.history_time = []
    self.history_temp = []
    self.history_humidity = []
    self.history_co2 = []
    self.history_voc = []
    self.history_radon = []
    self.device_states = {}
    self.histories = {}
    self.history_dirty = 0
    self.diagnostic_log = []
    self.alert_states = {}
    self.alert_last = {}
    self.load_history_file()
    self.use_device_history()
    self.load_device_state()
    self.log_event("START", "Driver " + self.DRIVER_VERSION + "; " + self.migration_status)
    self.read_stage = "idle"

    self.conn_cbp = tasmota.gen_cb(/e,o,u,h->self.on_conn(e,o,u,h))
    BLE.conn_cb(self.conn_cbp, self.cbuf)

    tasmota.add_fast_loop(/-> BLE.loop())

    # autoexec defers this driver until BLE is initialized, which is after
    # Tasmota's normal web_add_handler lifecycle event. Register the route now.
    self.web_add_handler()
  end

  def migrate_config()
    var old = int(persist.find("air2930_config_version", "1"))
    if old < self.CONFIG_VERSION
      persist.setmember("air2930_config_version", str(self.CONFIG_VERSION)); persist.save(true)
      return "Configuration migrated from v" + str(old) + " to v" + str(self.CONFIG_VERSION)
    end
    return "Configuration schema v" + str(self.CONFIG_VERSION)
  end

  def device_name()
    if self.active_index >= 0 && self.active_index < size(self.paired_names)
      return self.paired_names[self.active_index]
    end
    return "Airthings"
  end

  def set_device_name(index, name)
    if index < 0 || index >= size(self.paired_names) return nil end
    var n = string.tr(str(name), "<>\"'", "____")
    if size(n) < 1 n = "Airthings " + str(index + 1) end
    if size(n) > 32 n = n[0..31] end
    self.paired_names[index] = n; self.save_devices()
    self.discovery_sent = false
    self.log_event("CONFIG", "Device " + str(index + 1) + " named " + n)
  end

  def log_event(kind, message)
    var line = tasmota.strftime("%Y-%m-%d %H:%M:%S", tasmota.rtc('local')) + " [" + kind + "] " + message
    self.diagnostic_log.push(line)
    if size(self.diagnostic_log) > 50 self.diagnostic_log.remove(0) end
  end

  def health_score()
    var score = 100
    if self.stale() score -= 40 end
    score -= self.consecutive_failures * 12
    if self.last_rssi != nil && self.last_rssi < -85 score -= 20 elif self.last_rssi != nil && self.last_rssi < -75 score -= 10 end
    if self.battery != nil && self.battery < 20 score -= 20 elif self.battery != nil && self.battery < 40 score -= 10 end
    if score < 0 score = 0 end
    return score
  end

  def health_text()
    var s = self.health_score()
    if s >= 80 return "Healthy" end
    if s >= 50 return "Warning" end
    return "Offline"
  end

  def matter_air_quality()
    if self.co2 == nil return 0 end
    if self.co2 <= 750 return 1 end
    if self.co2 <= 1000 return 2 end
    if self.co2 <= 1250 return 3 end
    if self.co2 <= 1500 return 4 end
    if self.co2 <= 1750 return 5 end
    return 6
  end

  def load_history_file()
    try
      var f = open("/airthings_history.json", "r")
      var h = json.load(f.read()); f.close()
      if h != nil self.histories = h end
    except .. as e, m
      self.histories = {}
    end
  end

  def save_history_file()
    try
      var f = open("/airthings_history.json", "w")
      f.write(json.dump(self.histories)); f.close(); self.history_dirty = 0
    except .. as e, m
      self.log_event("ERROR", "History save failed: " + str(m))
    end
  end

  def use_device_history()
    if size(self.mac_hex) != 12 return nil end
    var h = self.histories.find(self.mac_hex, nil)
    if h == nil
      h = {'time':[], 'temperature':[], 'humidity':[], 'co2':[], 'voc':[], 'radon':[]}
      self.histories[self.mac_hex] = h
    end
    self.history_time = h['time']; self.history_temp = h['temperature']; self.history_humidity = h['humidity']
    self.history_co2 = h['co2']; self.history_voc = h['voc']; self.history_radon = h['radon']
  end

  def save_device_state()
    self.device_states[self.mac_hex] = {'last':self.last_read_text, 'age':self.seconds_since_read,
      'temperature':self.temperature, 'humidity':self.humidity, 'pressure':self.pressure, 'co2':self.co2,
      'voc':self.voc, 'radon_short':self.radon_short, 'radon_long':self.radon_long, 'light':self.light_raw,
      'battery':self.battery, 'battery_mv':self.battery_mv, 'rssi':self.last_rssi}
  end

  def load_device_state()
    var s = self.device_states.find(self.mac_hex, nil)
    if s == nil return nil end
    self.last_read_text=s['last']; self.seconds_since_read=s['age']; self.temperature=s['temperature']
    self.humidity=s['humidity']; self.pressure=s['pressure']; self.co2=s['co2']; self.voc=s['voc']
    self.radon_short=s['radon_short']; self.radon_long=s['radon_long']; self.light_raw=s['light']
    self.battery=s['battery']; self.battery_mv=s['battery_mv']; self.last_rssi=s['rssi']; self.last_read_ok=true
  end

  # ---------------------------------------------------------------------------
  # Formatting helpers
  # ---------------------------------------------------------------------------
  def hex2(v)
    return string.format("%02X", v)
  end

  def clean_mac(mac)
    return string.tr(string.tr(mac, ":", ""), "-", "")
  end

  def mac_from_adv()
    var s = ""
    for i:0..5
      s += self.hex2(self.abuf[i])
    end
    return s
  end

  def signed_rssi(v)
    if v > 127
      return v - 256
    end
    return v
  end

  def u16le(pos)
    return self.cbuf[pos] + (self.cbuf[pos + 1] * 256)
  end

  def valid_radon(v)
    if v >= 0 && v <= 16383
      return v
    end
    return nil
  end

  def val_or_dash(v)
    if v == nil
      return "-"
    end
    return str(v)
  end

  def json_or_null(v)
    if v == nil return "null" end
    return str(v)
  end

  def bq_to_pcil(v)
    if v == nil
      return nil
    end
    return v / 37.0
  end

  # ---------------------------------------------------------------------------
  # BLE scan / pair
  # ---------------------------------------------------------------------------
  def start_scan(seconds)
    self.dev_macs = []
    self.dev_types = []
    self.dev_rssi = []
    self.dev_serials = []
    self.scan_left = seconds
    self.scan_active = true
    self.status = "Scanning for Airthings BLE advertisements"

    self.adv_cbp = tasmota.gen_cb(/svc,manu->self.on_adv(svc,manu))
    BLE.adv_cb(self.adv_cbp, self.abuf)
  end

  def stop_scan()
    if self.scan_active
      BLE.adv_cb(nil)
    end
    self.scan_active = false
    self.scan_left = 0
  end

  def remember_device(mac, typ, rssi, serial)
    if mac == self.mac_hex self.last_rssi = rssi end
    var found = -1
    for i:0..size(self.dev_macs)-1
      if self.dev_macs[i] == mac
        found = i
      end
    end

    if found < 0
      if size(self.dev_macs) < 12
        self.dev_macs.push(mac)
        self.dev_types.push(typ)
        self.dev_rssi.push(rssi)
        self.dev_serials.push(serial)
      end
    else
      self.dev_types[found] = typ
      self.dev_rssi[found] = rssi
      self.dev_serials[found] = serial
    end
  end

  def on_adv(svc, manu)
    # Advertisement header is a packed berryAdvPacket_t.
    # Data layout from Tasmota docs:
    # bytes 0..5 = MAC, byte 6 = address type, byte 7 = RSSI, byte 8 = payload length
    var mac = self.mac_from_adv()
    var typ = self.abuf[6]
    var rssi = self.signed_rssi(self.abuf[7])
    var serial = ""
    if mac == self.mac_hex self.last_rssi = rssi end

    # Airthings manufacturer data starts with company id 0x0334, then 32-bit serial LE.
    if manu != 0
      var company = self.abuf[manu] + (self.abuf[manu + 1] * 256)
      if company == 0x0334
        var sn = self.abuf[manu + 2] + (self.abuf[manu + 3] * 256) + (self.abuf[manu + 4] * 65536) + (self.abuf[manu + 5] * 16777216.0)
        serial = string.format("%.0f", sn)
        self.remember_device(mac, typ, rssi, serial)
      end
    end
  end

  def pair(mac, typ)
    self.mac_hex = self.clean_mac(mac)
    self.addr_type = typ
    self.paired = size(self.mac_hex) == 12

    if self.paired
      var found = -1
      for i:0..size(self.paired_macs)-1 if self.paired_macs[i] == self.mac_hex found = i end end
      if found < 0 && size(self.paired_macs) < 2
        self.paired_macs.push(self.mac_hex); self.paired_types.push(self.addr_type)
        self.paired_names.push("Airthings " + str(size(self.paired_macs))); found = size(self.paired_macs)-1
      end
      if found >= 0 self.active_index = found; self.paired_types[found] = self.addr_type end
      self.save_devices()
      persist.setmember("air2930_mac", self.mac_hex)
      persist.setmember("air2930_type", str(self.addr_type))
      persist.save(true)
      self.stop_scan()
      self.status = "Paired to " + self.mac_hex
      self.poll_count = self.poll_seconds
      self.read_now()
    else
      self.status = "Invalid MAC"
    end
  end

  def save_devices()
    persist.setmember("air2930_devices", json.dump(self.paired_macs))
    persist.setmember("air2930_device_types", json.dump(self.paired_types))
    persist.setmember("air2930_device_names", json.dump(self.paired_names)); persist.save(true)
  end

  def select_device(index)
    if index < 0 || index >= size(self.paired_macs) return nil end
    if size(self.mac_hex) == 12 self.save_device_state() end
    self.active_index = index; self.mac_hex = self.paired_macs[index]; self.addr_type = self.paired_types[index]
    self.paired = true; self.status = "Selected " + self.mac_hex; self.poll_count = self.poll_seconds
    self.use_device_history(); self.load_device_state()
  end

  def next_device()
    if size(self.paired_macs) < 2 return nil end
    self.save_device_state()
    self.active_index = (self.active_index + 1) % size(self.paired_macs)
    self.mac_hex = self.paired_macs[self.active_index]; self.addr_type = self.paired_types[self.active_index]
    self.use_device_history(); self.load_device_state()
  end

  def unpair()
    self.stop_scan()
    if size(self.paired_macs) > 0
      self.paired_macs.remove(self.active_index); self.paired_types.remove(self.active_index)
      self.paired_names.remove(self.active_index)
    end
    self.active_index = 0
    self.mac_hex = size(self.paired_macs) > 0 ? self.paired_macs[0] : ""
    self.addr_type = size(self.paired_types) > 0 ? self.paired_types[0] : 0
    self.paired = size(self.mac_hex) == 12
    self.save_devices()
    persist.remove("air2930_mac")
    persist.remove("air2930_type")
    persist.save(true)
    self.status = "Unpaired"
  end

  def set_poll(seconds)
    if seconds < 15 seconds = 15 end
    if seconds > 86400 seconds = 86400 end
    self.poll_seconds = seconds
    self.poll_count = 0
    persist.setmember("air2930_poll", str(seconds))
    persist.save(true)
  end

  def set_units(temp_unit, pressure_unit, radon_unit, mqtt_units)
    if temp_unit == "F" self.temp_unit = "F" else self.temp_unit = "C" end
    if pressure_unit == "inHg" self.pressure_unit = "inHg" else self.pressure_unit = "hPa" end
    if radon_unit == "pCi/L" self.radon_unit = "pCi/L" else self.radon_unit = "Bq/m3" end
    self.mqtt_display_units = mqtt_units == "1"
    persist.setmember("air2930_temp_unit", self.temp_unit)
    persist.setmember("air2930_pressure_unit", self.pressure_unit)
    persist.setmember("air2930_radon_unit", self.radon_unit)
    persist.setmember("air2930_mqtt_units", self.mqtt_display_units ? "1" : "0")
    persist.save(true)
  end

  def display_temp()
    if self.temperature == nil return "-" end
    if self.temp_unit == "F" return string.format("%.2f", self.temperature * 9.0 / 5.0 + 32.0) end
    return string.format("%.2f", self.temperature)
  end

  def display_pressure()
    if self.pressure == nil return "-" end
    if self.pressure_unit == "inHg" return string.format("%.2f", self.pressure * 0.0295299830714) end
    return string.format("%.1f", self.pressure)
  end

  def display_radon(value)
    if value == nil return "-" end
    if self.radon_unit == "pCi/L" return string.format("%.2f", self.bq_to_pcil(value)) end
    return str(value)
  end

  def stale()
    return self.seconds_since_read < 0 || self.seconds_since_read > self.poll_seconds * 2
  end

  def age_text()
    if self.seconds_since_read < 0 return "Never" end
    if self.seconds_since_read < 60 return str(self.seconds_since_read) + " sec ago" end
    if self.seconds_since_read < 3600 return str(int(self.seconds_since_read / 60)) + " min ago" end
    return string.format("%.1f hours ago", self.seconds_since_read / 3600.0)
  end

  def set_calibration(t, h, p, c)
    self.cal_temp = real(t); self.cal_humidity = real(h)
    self.cal_pressure = real(p); self.cal_co2 = int(c)
    persist.setmember("air2930_cal_temp", str(self.cal_temp))
    persist.setmember("air2930_cal_humidity", str(self.cal_humidity))
    persist.setmember("air2930_cal_pressure", str(self.cal_pressure))
    persist.setmember("air2930_cal_co2", str(self.cal_co2)); persist.save(true)
  end

  def set_alerts(co2, voc, radon, hum_low, hum_high, battery)
    self.alert_co2 = int(co2); self.alert_voc = int(voc); self.alert_radon = int(radon)
    self.alert_humidity_low = int(hum_low); self.alert_humidity_high = int(hum_high)
    self.alert_battery = int(battery)
    persist.setmember("air2930_alert_co2", str(self.alert_co2))
    persist.setmember("air2930_alert_voc", str(self.alert_voc))
    persist.setmember("air2930_alert_radon", str(self.alert_radon))
    persist.setmember("air2930_alert_hum_low", str(self.alert_humidity_low))
    persist.setmember("air2930_alert_hum_high", str(self.alert_humidity_high))
    persist.setmember("air2930_alert_battery", str(self.alert_battery)); persist.save(true)
  end

  def set_alert_cooldown(seconds)
    var s = int(seconds); if s < 60 s = 60 end; if s > 86400 s = 86400 end
    self.alert_cooldown = s
    persist.setmember("air2930_alert_cooldown", str(s)); persist.save(true)
  end

  def history_push(arr, value)
    arr.push(value)
    if size(arr) > 288 arr.remove(0) end
  end

  def add_history()
    self.history_push(self.history_time, self.last_read_text)
    self.history_push(self.history_temp, self.temperature)
    self.history_push(self.history_humidity, self.humidity)
    self.history_push(self.history_co2, self.co2)
    self.history_push(self.history_voc, self.voc)
    self.history_push(self.history_radon, self.radon_short)
    self.history_dirty += 1
    if self.history_dirty >= 12 self.save_history_file() end
  end

  def alert_eval(id, trigger, clear, message)
    var key = self.mac_hex + "_" + id
    var active = self.alert_states.find(key, false)
    var last = int(self.alert_last.find(key, -86400))
    if trigger && (!active || self.uptime_seconds - last >= self.alert_cooldown)
      self.alert_states[key] = true; self.alert_last[key] = self.uptime_seconds
      tasmota.cmd("Publish tele/airthings2930/ALERT {\"State\":\"ALERT\",\"Alert\":\"" + message + "\",\"MAC\":\"" + self.mac_hex + "\",\"Name\":\"" + self.device_name() + "\"}")
      self.log_event("ALERT", message)
    elif active && clear
      self.alert_states[key] = false; self.alert_last[key] = self.uptime_seconds
      tasmota.cmd("Publish tele/airthings2930/ALERT {\"State\":\"CLEAR\",\"Alert\":\"" + message + "\",\"MAC\":\"" + self.mac_hex + "\",\"Name\":\"" + self.device_name() + "\"}")
      self.log_event("CLEAR", message)
    end
  end

  def check_alerts()
    if self.co2 != nil self.alert_eval("co2", self.co2 >= self.alert_co2, self.co2 <= self.alert_co2 - 100, "CO2 high") end
    if self.voc != nil self.alert_eval("voc", self.voc >= self.alert_voc, self.voc <= self.alert_voc - 25, "VOC high") end
    if self.radon_short != nil self.alert_eval("radon", self.radon_short >= self.alert_radon, self.radon_short <= self.alert_radon - 10, "Radon high") end
    if self.humidity != nil
      self.alert_eval("hum_low", self.humidity <= self.alert_humidity_low, self.humidity >= self.alert_humidity_low + 3, "Humidity low")
      self.alert_eval("hum_high", self.humidity >= self.alert_humidity_high, self.humidity <= self.alert_humidity_high - 3, "Humidity high")
    end
    if self.battery != nil self.alert_eval("battery", self.battery <= self.alert_battery, self.battery >= self.alert_battery + 5, "Battery low") end
  end

  # ---------------------------------------------------------------------------
  # BLE GATT read
  # ---------------------------------------------------------------------------
  def read_now()
    if !self.paired
      self.read_active = false
      self.status = "Not paired"
      return nil
    end

    self.status = "Reading " + self.mac_hex
    self.read_active = true
    self.read_started_second = self.uptime_seconds
    self.read_stage = "sensors"
    self.poll_count = 0
    BLE.set_MAC(bytes(self.mac_hex), self.addr_type)
    BLE.set_svc(self.SVC_UUID, true)
    BLE.set_chr(self.DATA_UUID)

    # 11 = read characteristic, then disconnect. Callback op will be 1.
    BLE.run(11, true)
  end

  def mark_failure(message)
    self.read_active = false
    self.last_read_ok = false
    self.last_error = message
    self.status = message
    self.read_failures += 1
    self.consecutive_failures += 1
    self.log_event("READ", message)
    if self.retry_count < 3
      self.retry_count += 1
      self.retry_wait = 5 * (1 << (self.retry_count - 1))
      self.status = message + "; retry in " + str(self.retry_wait) + "s"
    end
  end

  def on_conn(error, op, uuid, handle)
    if error != 0
      # Operation 11 reads once and then disconnects. Some Airthings devices
      # report a NimBLE disconnect status (for example 534) after the payload
      # has already been delivered successfully. Do not discard that reading.
      if op == 5 && self.last_read_ok
        self.status = "Last read OK"
        return nil
      end
      if self.read_stage == "battery"
        self.read_stage = "idle"
        self.read_active = false
        self.status = "Last read OK (battery unavailable)"
        self.last_error = "Battery BLE error " + str(error) + " op " + str(op)
        return nil
      end
      self.mark_failure("BLE error " + str(error) + " op " + str(op))
      return nil
    end

    if op == 3 && self.read_stage == "battery"
      self.status = "Battery subscribed"
      tasmota.set_timer(200, /->self.send_battery_command())
    elif op == 103 && self.read_stage == "battery"
      self.decode_battery()
      BLE.run(5)
    elif op == 1
      if self.read_stage == "battery"
        self.decode_battery()
      else
        self.decode_payload()
      end
    end
  end

  def read_battery()
    self.read_stage = "battery"
    self.read_active = true
    self.status = "Reading battery " + self.mac_hex
    BLE.set_MAC(bytes(self.mac_hex), self.addr_type)
    BLE.set_svc(self.SVC_UUID, true)
    BLE.set_chr(self.BATTERY_UUID)
    BLE.run(3, true)
  end

  def send_battery_command()
    if self.read_stage != "battery" return nil end
    self.status = "Battery command sent"
    self.cbuf[0] = 1
    self.cbuf[1] = 0x6D
    BLE.run(2, true)
  end

  def decode_battery()
    var n = self.cbuf[0]
    # Command 0x6D response contains battery voltage in millivolts at bytes 26-27.
    if n >= 28 && self.cbuf[1] == 0x6D
      var mv = self.cbuf[27] + (self.cbuf[28] << 8)
      self.battery_mv = mv
      self.battery = self.battery_percent(mv)
      self.last_error = ""
    else
      self.last_error = "Battery response invalid (" + str(n) + " bytes)"
    end
    self.read_stage = "idle"
    self.read_active = false
    self.status = "Last read OK"
    self.save_device_state()
    self.publish_mqtt()
    self.update_matter()
    self.check_alerts()
  end

  def battery_percent(mv)
    # Match sensor.airthings_wave: linear 2.2 V = 0% to 3.2 V = 100%.
    if mv <= 2200 return 0 end
    if mv >= 3200 return 100 end
    return int(((mv - 2200) * 100 + 500) / 1000)
  end

  def decode_payload()
    var n = self.cbuf[0]
    self.raw_hex = self.cbuf[1..n].tohex()

    # Wave Plus official reader unpacks '<BBBBHHHHHHHH' = 20 data bytes.
    # Needed values:
    # byte 0 version
    # byte 1 humidity raw / 2
    # bytes 4-5 radon short Bq/m3
    # bytes 6-7 radon long Bq/m3
    # bytes 8-9 temperature / 100 C
    # bytes 10-11 pressure / 50 hPa
    # bytes 12-13 CO2 ppm
    # bytes 14-15 VOC ppb
    if n < 16
      self.mark_failure("Payload too short: " + str(n))
      return nil
    end

    self.version = self.cbuf[1]
    if self.version != 1
      self.mark_failure("Unknown payload version: " + str(self.version))
      return nil
    end

    self.humidity = self.cbuf[2] / 2.0 + self.cal_humidity
    self.light_raw = self.cbuf[3]
    self.radon_short = self.valid_radon(self.u16le(5))
    self.radon_long = self.valid_radon(self.u16le(7))
    self.temperature = self.u16le(9) / 100.0 + self.cal_temp
    self.pressure = self.u16le(11) / 50.0 + self.cal_pressure
    self.co2 = self.u16le(13) + self.cal_co2
    self.voc = self.u16le(15)

    self.last_read_ok = true
    self.read_active = false
    self.last_error = ""
    self.status = "Last read OK"
    self.last_read_epoch = tasmota.rtc('local')
    self.last_read_text = tasmota.strftime("%Y-%m-%d %H:%M:%S", self.last_read_epoch)
    self.seconds_since_read = 0
    self.last_read_duration = self.uptime_seconds - self.read_started_second
    self.read_successes += 1
    self.consecutive_failures = 0
    self.retry_count = 0
    self.retry_wait = 0
    self.add_history()
    self.save_device_state()
    self.log_event("READ", self.device_name() + " read OK in " + str(self.last_read_duration) + "s")

    self.publish_mqtt()
    self.update_matter()
    # Allow the one-shot sensor connection to finish disconnecting before
    # starting the command/notification transaction on the same BLE client.
    tasmota.set_timer(5000, /->self.read_battery())
  end

  # ---------------------------------------------------------------------------
  # Tasmota SENSOR JSON and MQTT
  # ---------------------------------------------------------------------------
  def json_body()
    var pcil_short = self.bq_to_pcil(self.radon_short)
    var pcil_long = self.bq_to_pcil(self.radon_long)

    var s = "{"
    if self.mqtt_display_units
      s += "\"Temperature\":" + (self.temperature == nil ? "null" : self.display_temp())
      s += ",\"TemperatureUnit\":\"" + self.temp_unit + "\""
    else
      s += "\"Temperature\":" + self.json_or_null(self.temperature)
      s += ",\"TemperatureUnit\":\"C\""
    end
    s += ",\"Humidity\":" + self.json_or_null(self.humidity)
    if self.mqtt_display_units
      s += ",\"Pressure\":" + (self.pressure == nil ? "null" : self.display_pressure())
      s += ",\"PressureUnit\":\"" + self.pressure_unit + "\""
      s += ",\"RadonShort\":" + (self.radon_short == nil ? "null" : self.display_radon(self.radon_short))
      s += ",\"RadonLong\":" + (self.radon_long == nil ? "null" : self.display_radon(self.radon_long))
      s += ",\"RadonUnit\":\"" + self.radon_unit + "\""
    else
      s += ",\"Pressure\":" + self.json_or_null(self.pressure)
      s += ",\"PressureUnit\":\"hPa\""
    end
    s += ",\"CarbonDioxide\":" + self.json_or_null(self.co2)
    s += ",\"TVOC\":" + self.json_or_null(self.voc)
    s += ",\"RadonShortBq\":" + self.json_or_null(self.radon_short)
    s += ",\"RadonLongBq\":" + self.json_or_null(self.radon_long)
    s += ",\"RadonShortpCiL\":" + self.json_or_null(pcil_short)
    s += ",\"RadonLongpCiL\":" + self.json_or_null(pcil_long)
    s += ",\"LightRaw\":" + self.json_or_null(self.light_raw)
    s += ",\"Battery\":" + self.json_or_null(self.battery)
    s += ",\"BatteryMillivolts\":" + self.json_or_null(self.battery_mv)
    s += ",\"Stale\":" + (self.stale() ? "true" : "false")
    s += ",\"Name\":\"" + self.device_name() + "\""
    s += ",\"Health\":\"" + self.health_text() + "\""
    s += ",\"HealthScore\":" + str(self.health_score())
    s += ",\"DriverVersion\":\"" + self.DRIVER_VERSION + "\""
    s += "}"
    return s
  end

  def publish_mqtt()
    if !self.last_read_ok
      return nil
    end
    var payload = "{\"Airthings2930\":" + self.json_body() + "}"
    tasmota.cmd("Publish tele/airthings2930/" + self.mac_hex + "/SENSOR " + payload)
    # Preserve the original topic for existing single-device automations.
    tasmota.cmd("Publish tele/airthings2930/SENSOR " + payload)
    if self.discovery_enabled && !self.discovery_sent self.publish_discovery() end
  end

  def discovery_sensor(id, name, key, unit, device_class)
    var topic = "homeassistant/sensor/airthings2930_" + self.mac_hex + "/" + id + "/config"
    var p = "{\"name\":\"" + name + "\",\"unique_id\":\"air2930_" + self.mac_hex + "_" + id + "\",\"state_topic\":\"tele/airthings2930/" + self.mac_hex + "/SENSOR\",\"value_template\":\"{{ value_json.Airthings2930." + key + " }}\",\"unit_of_measurement\":\"" + unit + "\",\"device\":{\"identifiers\":[\"air2930_" + self.mac_hex + "\"],\"name\":\"" + self.device_name() + "\",\"manufacturer\":\"Airthings\",\"model\":\"Wave Plus 2930\"}"
    if device_class != "" p += ",\"device_class\":\"" + device_class + "\"" end
    p += "}"
    tasmota.cmd("Publish2 " + topic + " " + p)
  end

  def publish_discovery()
    var tu = self.mqtt_display_units ? self.temp_unit : "C"
    var pu = self.mqtt_display_units ? self.pressure_unit : "hPa"
    self.discovery_sensor("temperature", "Temperature", "Temperature", "deg " + tu, "temperature")
    self.discovery_sensor("humidity", "Humidity", "Humidity", "%", "humidity")
    self.discovery_sensor("pressure", "Pressure", "Pressure", pu, "pressure")
    self.discovery_sensor("co2", "CO2", "CarbonDioxide", "ppm", "carbon_dioxide")
    self.discovery_sensor("voc", "VOC", "TVOC", "ppb", "volatile_organic_compounds_parts")
    self.discovery_sensor("battery", "Battery", "Battery", "%", "battery")
    self.discovery_sensor("radon", "Radon 24h", self.mqtt_display_units ? "RadonShort" : "RadonShortBq", self.mqtt_display_units ? self.radon_unit : "Bq/m3", "")
    self.discovery_sent = true
  end

  def set_discovery(enabled)
    self.discovery_enabled = enabled
    self.discovery_sent = false
    persist.setmember("air2930_discovery", enabled ? "1" : "0"); persist.save(true)
    if enabled self.publish_discovery() end
  end

  def json_append()
    if !self.last_read_ok
      return nil
    end
    tasmota.response_append(",\"Airthings2930\":" + self.json_body())
  end

  # ---------------------------------------------------------------------------
  # Matter updates
  # ---------------------------------------------------------------------------
  def update_matter()
    if !self.last_read_ok
      return nil
    end

    # These names must match virtual endpoints created in Tasmota Configure Matter.
    var prefix = self.active_index == 0 ? "AT_" : "AT2_"
    # Temperature is in 1/100 C; Humidity is in 1/100 percent; Pressure is hPa.
    if self.temperature != nil
      tasmota.cmd("MtrUpdate {\"Name\":\"" + prefix + "Temp\",\"Temperature\":" + str(int(self.temperature * 100)) + "}")
    end
    if self.humidity != nil
      tasmota.cmd("MtrUpdate {\"Name\":\"" + prefix + "Humidity\",\"Humidity\":" + str(int(self.humidity * 100)) + "}")
    end
    if self.pressure != nil
      tasmota.cmd("MtrUpdate {\"Name\":\"" + prefix + "Pressure\",\"Pressure\":" + str(self.pressure) + "}")
    end
    if self.light_raw != nil
      tasmota.cmd("MtrUpdate {\"Name\":\"" + prefix + "Light\",\"Illuminance\":" + str(self.light_raw) + "}")
    end
    if self.co2 != nil && self.voc != nil
      tasmota.cmd("MtrUpdate {\"Name\":\"" + prefix + "AirQuality\",\"AirQuality\":" + str(self.matter_air_quality()) + ",\"CO2\":" + str(self.co2) + ",\"TVOC\":" + str(self.voc) + "}")
    end

    # Workaround until Tasmota Matter has a direct Radon MtrUpdate attribute.
    # Create these as virtual Pressure endpoints and name them clearly.
    if self.radon_short != nil
      tasmota.cmd("MtrUpdate {\"Name\":\"" + prefix + "RadonShort\",\"Pressure\":" + str(self.radon_short) + "}")
    end
    if self.radon_long != nil
      tasmota.cmd("MtrUpdate {\"Name\":\"" + prefix + "RadonLong\",\"Pressure\":" + str(self.radon_long) + "}")
    end
  end

  # ---------------------------------------------------------------------------
  # Tasmota main web page sensor display
  # ---------------------------------------------------------------------------
  def web_sensor()
    if webserver.has_arg("at_read")
      self.read_now()
    end
    var next_read = self.poll_seconds - self.poll_count
    if next_read < 0 next_read = 0 end
    var msg = "{s}Airthings 2930{m}" + self.status + (self.stale() ? " (stale)" : "") + "{e}"
    if self.paired
      msg += "{s}Airthings MAC{m}" + self.mac_hex + "{e}"
    end
    msg += "{s}Last reading{m}" + self.last_read_text + " (" + self.age_text() + "){e}"
    msg += "{s}Next reading{m}" + str(next_read) + " seconds{e}"
    if self.last_read_ok
      msg += "{s}Temperature{m}" + self.display_temp() + " deg " + self.temp_unit + "{e}"
      msg += string.format("{s}Humidity{m}%.1f %%{e}", self.humidity)
      msg += "{s}Pressure{m}" + self.display_pressure() + " " + self.pressure_unit + "{e}"
      msg += "{s}CO2{m}" + str(self.co2) + " ppm{e}"
      msg += "{s}VOC{m}" + str(self.voc) + " ppb{e}"
      msg += "{s}Light{m}" + str(self.light_raw) + " raw{e}"
      msg += "{s}Battery{m}" + self.val_or_dash(self.battery) + " %{e}"
      msg += "{s}Radon 24h{m}" + self.display_radon(self.radon_short) + " " + self.radon_unit + "{e}"
      msg += "{s}Radon long{m}" + self.display_radon(self.radon_long) + " " + self.radon_unit + "{e}"
    end
    tasmota.web_send_decimal(msg)
  end

  def web_add_main_button()
    webserver.content_send("<table style='width:100%'><tr>")
    webserver.content_send("<td style='width:50%'><button onclick='la(\"&at_read=1\");'>Read Airthings Now</button></td>")
    webserver.content_send("<td style='width:50%'><form action='/airthings' method='get'><button>Airthings Settings</button></form></td>")
    webserver.content_send("</tr></table>")
  end

  # ---------------------------------------------------------------------------
  # Custom web page
  # ---------------------------------------------------------------------------
  def web_add_handler()
    webserver.on("/airthings", /->self.page_airthings())
    webserver.on("/airthings_api", /->self.page_airthings_api())
    webserver.on("/airthings_devices", /->self.page_airthings_devices())
    webserver.on("/airthings_history", /->self.page_airthings_history())
    webserver.on("/airthings_history.csv", /->self.page_airthings_csv())
    webserver.on("/airthings_diagnostics", /->self.page_airthings_diagnostics())
    webserver.on("/airthings_backup", /->self.page_airthings_backup())
    webserver.on("/airthings_restore_preview", /->self.page_restore_preview())
  end

  def page_airthings_backup()
    if !webserver.check_privileged_access() return nil end
    import json
    var cfg = {'version':self.CONFIG_VERSION, 'driver_version':self.DRIVER_VERSION, 'mac':self.mac_hex,
      'type':self.addr_type, 'devices':self.paired_macs, 'device_types':self.paired_types,
      'device_names':self.paired_names, 'poll':self.poll_seconds,
      'temp_unit':self.temp_unit, 'pressure_unit':self.pressure_unit, 'radon_unit':self.radon_unit,
      'mqtt_units':self.mqtt_display_units, 'cal_temp':self.cal_temp, 'cal_humidity':self.cal_humidity,
      'cal_pressure':self.cal_pressure, 'cal_co2':self.cal_co2, 'alert_co2':self.alert_co2,
      'alert_voc':self.alert_voc, 'alert_radon':self.alert_radon, 'alert_hum_low':self.alert_humidity_low,
      'alert_hum_high':self.alert_humidity_high, 'alert_battery':self.alert_battery,
      'discovery':self.discovery_enabled, 'alert_cooldown':self.alert_cooldown}
    webserver.content_open(200, "application/json")
    webserver.content_send(json.dump(cfg)); webserver.content_close()
  end

  def restore_config(text)
    var result = self.validate_config(text)
    if !result['valid'] self.log_event("CONFIG", "Restore rejected: " + result['message']); return false end
    var c = result['config']
    self.set_poll(int(c.find('poll', self.poll_seconds)))
    self.set_units(str(c.find('temp_unit', self.temp_unit)), str(c.find('pressure_unit', self.pressure_unit)), str(c.find('radon_unit', self.radon_unit)), c.find('mqtt_units', false) ? "1" : "0")
    self.set_calibration(c.find('cal_temp', self.cal_temp), c.find('cal_humidity', self.cal_humidity), c.find('cal_pressure', self.cal_pressure), c.find('cal_co2', self.cal_co2))
    self.set_alerts(c.find('alert_co2', self.alert_co2), c.find('alert_voc', self.alert_voc), c.find('alert_radon', self.alert_radon), c.find('alert_hum_low', self.alert_humidity_low), c.find('alert_hum_high', self.alert_humidity_high), c.find('alert_battery', self.alert_battery))
    self.set_discovery(c.find('discovery', self.discovery_enabled))
    self.set_alert_cooldown(c.find('alert_cooldown', self.alert_cooldown))
    var ds = c.find('devices', nil)
    var ts = c.find('device_types', nil)
    if ds != nil && ts != nil
      self.paired_macs = ds; self.paired_types = ts
      self.paired_names = c.find('device_names', [])
      while size(self.paired_names) < size(self.paired_macs) self.paired_names.push("Airthings " + str(size(self.paired_names)+1)) end
      self.active_index = 0
      if size(ds) > 0 self.select_device(0); self.save_devices() end
    else
      var m = str(c.find('mac', self.mac_hex))
      if size(m) == 12 self.pair(m, int(c.find('type', self.addr_type))) end
    end
    self.log_event("CONFIG", "Configuration restored")
    return true
  end

  def validate_config(text)
    try
      var c = json.load(text)
      if c == nil return {'valid':false,'message':'JSON must be an object'} end
      var v = int(c.find('version', 0))
      if v < 1 || v > self.CONFIG_VERSION return {'valid':false,'message':'Unsupported configuration version'} end
      var poll = int(c.find('poll', self.poll_seconds))
      if poll < 15 || poll > 86400 return {'valid':false,'message':'Polling interval must be 15-86400'} end
      var ds = c.find('devices', [])
      var ts = c.find('device_types', [])
      if size(ds) > 2 || size(ds) != size(ts) return {'valid':false,'message':'Device arrays are invalid or exceed two devices'} end
      for m:ds
        if size(self.clean_mac(str(m))) != 12 return {'valid':false,'message':'Invalid device MAC'} end
      end
      return {'valid':true,'message':'Valid v' + str(v) + ' configuration for ' + str(size(ds)) + ' device(s)','config':c}
    except .. as e, m
      return {'valid':false,'message':'Invalid JSON: ' + str(m)}
    end
  end

  def page_restore_preview()
    if !webserver.check_privileged_access() return nil end
    var r = self.validate_config(webserver.arg("config"))
    var out = {'valid':r['valid'], 'message':r['message']}
    webserver.content_open(200, "application/json"); webserver.content_send(json.dump(out)); webserver.content_close()
  end

  def array_json(arr, quoted)
    var s = "["
    for i:0..size(arr)-1
      if i > 0 s += "," end
      if quoted s += "\"" + str(arr[i]) + "\"" else s += self.json_or_null(arr[i]) end
    end
    return s + "]"
  end

  def page_airthings_history()
    if !webserver.check_privileged_access() return nil end
    var body = "{\"time\":" + self.array_json(self.history_time, true)
    body += ",\"temperature\":" + self.array_json(self.history_temp, false)
    body += ",\"humidity\":" + self.array_json(self.history_humidity, false)
    body += ",\"co2\":" + self.array_json(self.history_co2, false)
    body += ",\"voc\":" + self.array_json(self.history_voc, false)
    body += ",\"radon\":" + self.array_json(self.history_radon, false) + "}"
    webserver.content_open(200, "application/json"); webserver.content_send(body); webserver.content_close()
  end

  def page_airthings_csv()
    if !webserver.check_privileged_access() return nil end
    var s = "timestamp,temperature_c,humidity_percent,co2_ppm,voc_ppb,radon_bq_m3\n"
    for i:0..size(self.history_time)-1
      s += self.history_time[i] + "," + self.json_or_null(self.history_temp[i]) + "," + self.json_or_null(self.history_humidity[i])
      s += "," + self.json_or_null(self.history_co2[i]) + "," + self.json_or_null(self.history_voc[i]) + "," + self.json_or_null(self.history_radon[i]) + "\n"
    end
    webserver.content_open(200, "text/csv"); webserver.content_send(s); webserver.content_close()
  end

  def page_airthings_diagnostics()
    if !webserver.check_privileged_access() return nil end
    webserver.content_open(200, "application/json"); webserver.content_send(json.dump(self.diagnostic_log)); webserver.content_close()
  end

  # Canonical, read-only snapshot used by local integrations such as the
  # SmartThings LAN Edge driver. Unlike /airthings_api this returns every
  # paired sensor and never changes the active device or starts a BLE read.
  def page_airthings_devices()
    if !webserver.check_privileged_access() return nil end
    if size(self.mac_hex) == 12 self.save_device_state() end
    var devices = []
    for i:0..size(self.paired_macs)-1
      var mac = self.paired_macs[i]
      var state = self.device_states.find(mac, {})
      devices.push({
        'index':i, 'mac':mac, 'name':self.paired_names[i],
        'last':state.find('last', ''), 'temperature':state.find('temperature', nil),
        'humidity':state.find('humidity', nil), 'pressure':state.find('pressure', nil),
        'co2':state.find('co2', nil), 'voc':state.find('voc', nil),
        'radon_short':state.find('radon_short', nil), 'radon_long':state.find('radon_long', nil),
        'light':state.find('light', nil), 'battery':state.find('battery', nil),
        'battery_mv':state.find('battery_mv', nil), 'rssi':state.find('rssi', nil),
        'active':i == self.active_index
      })
    end
    var out = {'driver_version':self.DRIVER_VERSION, 'poll':self.poll_seconds, 'devices':devices}
    webserver.content_open(200, "application/json")
    webserver.content_send(json.dump(out))
    webserver.content_close()
  end

  def page_airthings_api()
    if !webserver.check_privileged_access() return nil end
    if webserver.has_arg("read") self.read_now() end

    var next_read = self.poll_seconds - self.poll_count
    if next_read < 0 next_read = 0 end
    var body = "{\"status\":\"" + self.status + "\""
    body += ",\"last\":\"" + self.last_read_text + "\""
    body += ",\"next\":" + str(next_read)
    body += ",\"poll\":" + str(self.poll_seconds)
    body += ",\"mac\":\"" + self.mac_hex + "\""
    body += ",\"name\":\"" + self.device_name() + "\""
    body += ",\"health\":\"" + self.health_text() + "\""
    body += ",\"health_score\":" + str(self.health_score())
    body += ",\"driver_version\":\"" + self.DRIVER_VERSION + "\""
    body += ",\"temperature\":\"" + self.display_temp() + "\""
    body += ",\"temperature_unit\":\"" + self.temp_unit + "\""
    body += ",\"humidity\":\"" + self.val_or_dash(self.humidity) + "\""
    body += ",\"pressure\":\"" + self.display_pressure() + "\""
    body += ",\"pressure_unit\":\"" + self.pressure_unit + "\""
    body += ",\"co2\":\"" + self.val_or_dash(self.co2) + "\""
    body += ",\"voc\":\"" + self.val_or_dash(self.voc) + "\""
    body += ",\"light\":\"" + self.val_or_dash(self.light_raw) + "\""
    body += ",\"battery\":\"" + self.val_or_dash(self.battery) + "\""
    body += ",\"battery_mv\":\"" + self.val_or_dash(self.battery_mv) + "\""
    body += ",\"age\":\"" + self.age_text() + "\""
    body += ",\"stale\":" + (self.stale() ? "true" : "false")
    body += ",\"successes\":" + str(self.read_successes)
    body += ",\"failures\":" + str(self.read_failures)
    body += ",\"consecutive_failures\":" + str(self.consecutive_failures)
    body += ",\"read_duration\":" + str(self.last_read_duration)
    body += ",\"rssi\":" + self.json_or_null(self.last_rssi)
    body += ",\"radon_short\":\"" + self.display_radon(self.radon_short) + "\""
    body += ",\"radon_long\":\"" + self.display_radon(self.radon_long) + "\""
    body += ",\"radon_unit\":\"" + self.radon_unit + "\""
    body += ",\"mqtt_display_units\":" + (self.mqtt_display_units ? "true" : "false")
    body += ",\"raw\":\"" + self.raw_hex + "\""
    body += ",\"error\":\"" + self.last_error + "\"}"
    webserver.content_open(200, "application/json")
    webserver.content_send(body)
    webserver.content_close()
  end

  def page_airthings()
    if !webserver.check_privileged_access()
      return nil
    end

    if webserver.has_arg("scan")
      self.start_scan(20)
    end
    if webserver.has_arg("stop")
      self.stop_scan()
    end
    if webserver.has_arg("read")
      self.read_now()
    end
    if webserver.has_arg("setpoll")
      self.set_poll(int(webserver.arg("poll")))
    end
    if webserver.has_arg("setunits")
      self.set_units(webserver.arg("temp_unit"), webserver.arg("pressure_unit"), webserver.arg("radon_unit"), webserver.arg("mqtt_units"))
    end
    if webserver.has_arg("setcal")
      self.set_calibration(webserver.arg("cal_temp"), webserver.arg("cal_humidity"), webserver.arg("cal_pressure"), webserver.arg("cal_co2"))
    end
    if webserver.has_arg("setalerts")
      self.set_alerts(webserver.arg("alert_co2"), webserver.arg("alert_voc"), webserver.arg("alert_radon"), webserver.arg("alert_hum_low"), webserver.arg("alert_hum_high"), webserver.arg("alert_battery"))
    end
    if webserver.has_arg("setcooldown") self.set_alert_cooldown(webserver.arg("alert_cooldown")) end
    if webserver.has_arg("setname") self.set_device_name(int(webserver.arg("index")), webserver.arg("device_name")) end
    if webserver.has_arg("restore") self.restore_config(webserver.arg("config")) end
    if webserver.has_arg("setdiscovery") self.set_discovery(webserver.arg("discovery") == "1") end
    if webserver.has_arg("select")
      self.select_device(int(webserver.arg("select"))); self.read_now()
    end
    if webserver.has_arg("unpair")
      self.unpair()
    end
    if webserver.has_arg("pair")
      var mac = webserver.arg("mac")
      var typ = int(webserver.arg("type"))
      self.pair(mac, typ)
    end

    webserver.content_start("Airthings 2930")
    webserver.content_send_style()

    webserver.content_send("<style>#atpage{max-width:720px;margin:0 auto;text-align:left}#atpage *{box-sizing:border-box}.at-head{text-align:center;margin:8px 0 14px}.at-card{border:1px solid rgba(128,128,128,.35);border-radius:12px;padding:14px;margin:10px 0;background:rgba(128,128,128,.07)}.at-card h3{margin:0 0 12px;text-align:left}.at-summary{display:grid;grid-template-columns:1fr 1fr;gap:8px}.at-stat{padding:9px 10px;border-radius:8px;background:rgba(128,128,128,.11)}.at-stat b{display:block;font-size:12px;opacity:.7;margin-bottom:3px}.at-actions{display:grid;grid-template-columns:repeat(4,1fr);gap:7px}.at-actions button,#atpage .at-save{width:100%;min-width:0;padding:9px 6px;margin:0;font-size:13px}.at-poll{display:grid;grid-template-columns:1fr 90px auto;gap:8px;align-items:end}.at-units{display:grid;grid-template-columns:1fr;gap:10px;margin-top:12px}.at-units select{max-width:220px}.at-units .at-save{max-width:220px}.at-poll label,.at-field label,.at-units label{display:block;font-size:12px;font-weight:bold;opacity:.75;margin-bottom:4px}.at-poll #poll,#atpage select,#atpage input[name=type],#atpage input[name=mac]{width:100%;display:block;padding:8px;margin:0}.at-note{font-size:11px;opacity:.7;margin:8px 0 0}.at-table{width:100%;border-collapse:collapse}.at-table td{padding:7px 5px;border-bottom:1px solid rgba(128,128,128,.2)}.at-table td:nth-child(2){text-align:right}.at-table td:last-child{width:70px;opacity:.7}.at-pair{display:grid;grid-template-columns:2fr 70px auto;gap:8px;align-items:end}.at-scroll{overflow-x:auto}.at-error{overflow-wrap:anywhere}.at-raw{font-family:monospace;font-size:14px;line-height:1.5;overflow-wrap:anywhere;word-break:break-all;margin-top:10px;padding:10px;border-radius:8px;background:rgba(128,128,128,.14);letter-spacing:.3px}.at-raw b{display:block;font-family:inherit;font-size:12px;margin-bottom:4px;opacity:.75}#atpage details summary{cursor:pointer;padding:4px 0;font-weight:bold}@media(max-width:520px){.at-summary{grid-template-columns:1fr}.at-actions{grid-template-columns:1fr 1fr}.at-poll{grid-template-columns:1fr 85px}.at-poll .at-save{grid-column:1/-1}.at-units select,.at-units .at-save{max-width:none}.at-pair{grid-template-columns:1fr 65px}.at-pair button{grid-column:1/-1}}</style><div id='atpage'>")
    webserver.content_send("<h2 class='at-head'>Airthings Wave Plus</h2><section class='at-card'><div class='at-summary'>")
    webserver.content_send("<div class='at-stat'><b>Status</b><span id='at_status'>" + self.status + "</span></div>")
    webserver.content_send("<div class='at-stat'><b>Last reading</b><span id='at_last'>" + self.last_read_text + "</span><div class='at-note' id='at_age'>" + self.age_text() + "</div></div>")

    var next_read = self.poll_seconds - self.poll_count
    if next_read < 0
      next_read = 0
    end
    webserver.content_send("<div class='at-stat'><b>Next reading</b><span id='at_next'>" + str(next_read) + "</span> seconds</div>")
    webserver.content_send("<div class='at-stat'><b>Device</b><span id='at_name'>" + self.device_name() + "</span><div class='at-note'>" + self.mac_hex + "</div></div>")
    webserver.content_send("<div class='at-stat'><b>Sensor health</b><span id='at_health'>" + self.health_text() + "</span> (<span id='at_health_score'>" + str(self.health_score()) + "</span>/100)</div>")
    webserver.content_send("<div class='at-stat'><b>Driver</b>" + self.DRIVER_VERSION + "<div class='at-note'>" + self.compatibility_status + "</div></div></div></section>")
    webserver.content_send("<section class='at-card'><h3>Schedule</h3><form class='at-poll' method='get' action='/airthings'>")
    webserver.content_send("<div><label for='poll'>Polling interval</label><div class='at-note'>15 seconds to 24 hours</div></div><div><label for='poll'>Seconds</label><input id='poll' name='poll' type='number' min='15' max='86400' value='" + str(self.poll_seconds) + "'></div>")
    webserver.content_send("<button class='at-save' name='setpoll' value='1'>Save</button></form><p class='at-note'>Recommended: 300 seconds, matching the sensor's normal environmental update rate.</p></section>")
    webserver.content_send("<section class='at-card'><details><summary>Display units</summary><form class='at-units' method='get' action='/airthings'><div><label for='temp_unit'>Temperature</label><select id='temp_unit' name='temp_unit'>")
    if self.temp_unit == "C" webserver.content_send("<option value='C' selected>Celsius (C)</option><option value='F'>Fahrenheit (F)</option>") else webserver.content_send("<option value='C'>Celsius (C)</option><option value='F' selected>Fahrenheit (F)</option>") end
    webserver.content_send("</select></div><div><label for='pressure_unit'>Pressure</label><select id='pressure_unit' name='pressure_unit'>")
    if self.pressure_unit == "hPa" webserver.content_send("<option value='hPa' selected>hPa</option><option value='inHg'>inHg</option>") else webserver.content_send("<option value='hPa'>hPa</option><option value='inHg' selected>inHg</option>") end
    webserver.content_send("</select></div><div><label for='radon_unit'>Radon</label><select id='radon_unit' name='radon_unit'>")
    if self.radon_unit == "Bq/m3" webserver.content_send("<option value='Bq/m3' selected>Bq/m3</option><option value='pCi/L'>pCi/L</option>") else webserver.content_send("<option value='Bq/m3'>Bq/m3</option><option value='pCi/L' selected>pCi/L</option>") end
    webserver.content_send("</select></div><div><label for='mqtt_units'>MQTT published units</label><select id='mqtt_units' name='mqtt_units'>")
    if self.mqtt_display_units webserver.content_send("<option value='0'>Canonical C / hPa / Bq/m3</option><option value='1' selected>Use selected display units</option>") else webserver.content_send("<option value='0' selected>Canonical C / hPa / Bq/m3</option><option value='1'>Use selected display units</option>") end
    webserver.content_send("</select></div><button class='at-save' name='setunits' value='1'>Save units</button></form><p class='at-note'>Matter always uses protocol-standard Celsius and hPa. Matter apps perform their own localized display conversion.</p></details></section>")
    webserver.content_send("<script>function au(){fetch('/airthings_api').then(r=>r.text()).then(s=>{var d=JSON.parse(s.slice(0,s.indexOf('}')+1));for(var k in d){var e=document.getElementById('at_'+k);if(e)e.textContent=d[k];}});}function ar(){fetch('/airthings_api?read=1').then(()=>au());}setInterval(au,1000);</script>")

    webserver.content_send("<section class='at-card'><h3>Actions</h3><form class='at-actions' method='get' action='/airthings'>")
    webserver.content_send("<button type='button' onclick='ar()'>Read Now</button>")
    webserver.content_send("<button name='scan' value='1'>Scan BLE</button>")
    webserver.content_send("<button name='stop' value='1'>Stop Scan</button>")
    webserver.content_send("<button name='unpair' value='1'>Unpair</button></form>")

    if self.scan_active
      webserver.content_send("<p class='at-note'><b>Scanning:</b> " + str(self.scan_left) + " seconds remaining</p>")
    end
    webserver.content_send("</section>")

    webserver.content_send("<section class='at-card'><h3>Current readings</h3><table class='at-table'>")
    self.row_id("temperature", "Temperature", self.display_temp(), "deg " + self.temp_unit)
    self.row_id("humidity", "Humidity", self.val_or_dash(self.humidity), "%")
    self.row_id("pressure", "Pressure", self.display_pressure(), self.pressure_unit)
    self.row_id("co2", "CO2", self.val_or_dash(self.co2), "ppm")
    self.row_id("voc", "VOC", self.val_or_dash(self.voc), "ppb")
    self.row_id("light", "Light", self.val_or_dash(self.light_raw), "raw")
    self.row_id("battery", "Battery", self.val_or_dash(self.battery), "%")
    self.row_id("radon_short", "Radon 24h", self.display_radon(self.radon_short), self.radon_unit)
    self.row_id("radon_long", "Radon long-term", self.display_radon(self.radon_long), self.radon_unit)
    webserver.content_send("</table><p class='at-error'><b>Last error:</b> <span id='at_error'>" + self.last_error + "</span></p><div class='at-raw'><b>Raw payload</b><span id='at_raw'>" + self.raw_hex + "</span></div></section>")

    webserver.content_send("<section class='at-card'><details open><summary>Persistent history charts (latest 288 samples)</summary><p><a href='/airthings_history.csv'>Download current device CSV</a></p><canvas id='at_chart_co2' height='120'></canvas><canvas id='at_chart_temp' height='120'></canvas><canvas id='at_chart_radon' height='120'></canvas></details></section>")
    webserver.content_send("<script>function ac(id,a,label,color){var c=document.getElementById(id),x=c.getContext('2d'),w=c.width=c.clientWidth*devicePixelRatio,h=c.height=120*devicePixelRatio;x.clearRect(0,0,w,h);x.strokeStyle=color;x.lineWidth=2*devicePixelRatio;x.beginPath();var v=a.filter(n=>n!=null);if(!v.length)return;var lo=Math.min(...v),hi=Math.max(...v);if(hi==lo)hi=lo+1;a.forEach((n,i)=>{if(n==null)return;var px=i*w/Math.max(1,a.length-1),py=h-8-(n-lo)*(h-22)/(hi-lo);i?x.lineTo(px,py):x.moveTo(px,py)});x.stroke();x.fillStyle=color;x.font=(11*devicePixelRatio)+'px sans-serif';x.fillText(label+' '+lo.toFixed(1)+' - '+hi.toFixed(1),6*devicePixelRatio,13*devicePixelRatio)}fetch('/airthings_history').then(r=>r.json()).then(d=>{ac('at_chart_co2',d.co2,'CO2','#29a8e8');ac('at_chart_temp',d.temperature,'Temperature','#ef8b45');ac('at_chart_radon',d.radon,'Radon','#b78cff')});</script>")

    webserver.content_send("<section class='at-card'><details><summary>Calibration and alert thresholds</summary><h3>Calibration offsets</h3><form class='at-units' method='get' action='/airthings'>")
    webserver.content_send("<div><label>Temperature offset (C)</label><input name='cal_temp' value='" + str(self.cal_temp) + "'></div><div><label>Humidity offset (%)</label><input name='cal_humidity' value='" + str(self.cal_humidity) + "'></div><div><label>Pressure offset (hPa)</label><input name='cal_pressure' value='" + str(self.cal_pressure) + "'></div><div><label>CO2 offset (ppm)</label><input name='cal_co2' value='" + str(self.cal_co2) + "'></div><button class='at-save' name='setcal' value='1'>Save calibration</button></form>")
    webserver.content_send("<h3>Alert thresholds</h3><form class='at-units' method='get' action='/airthings'><div><label>CO2 high (ppm)</label><input name='alert_co2' value='" + str(self.alert_co2) + "'></div><div><label>VOC high (ppb)</label><input name='alert_voc' value='" + str(self.alert_voc) + "'></div><div><label>Radon high (Bq/m3)</label><input name='alert_radon' value='" + str(self.alert_radon) + "'></div><div><label>Humidity low (%)</label><input name='alert_hum_low' value='" + str(self.alert_humidity_low) + "'></div><div><label>Humidity high (%)</label><input name='alert_hum_high' value='" + str(self.alert_humidity_high) + "'></div><div><label>Battery low (%)</label><input name='alert_battery' value='" + str(self.alert_battery) + "'></div><button class='at-save' name='setalerts' value='1'>Save alerts</button></form><form class='at-units' method='get' action='/airthings'><div><label>Alert reminder cooldown (seconds)</label><input name='alert_cooldown' min='60' max='86400' value='" + str(self.alert_cooldown) + "'></div><button class='at-save' name='setcooldown' value='1'>Save cooldown</button></form><p class='at-note'>Alerts clear only after a safe margin is reached, preventing threshold chatter.</p></details></section>")

    webserver.content_send("<section class='at-card'><details><summary>Diagnostics and compatibility</summary><table class='at-table'><tr><td>Battery voltage</td><td><b id='at_battery_mv'>" + self.val_or_dash(self.battery_mv) + "</b></td><td>mV</td></tr><tr><td>BLE RSSI</td><td><b id='at_rssi'>" + self.val_or_dash(self.last_rssi) + "</b></td><td>dBm</td></tr><tr><td>Successful reads</td><td id='at_successes'>" + str(self.read_successes) + "</td><td></td></tr><tr><td>Failed reads</td><td id='at_failures'>" + str(self.read_failures) + "</td><td></td></tr><tr><td>Consecutive failures</td><td id='at_consecutive_failures'>" + str(self.consecutive_failures) + "</td><td></td></tr><tr><td>Last connection</td><td id='at_read_duration'>" + str(self.last_read_duration) + "</td><td>sec</td></tr></table><p class='at-note'>" + self.migration_status + ". " + self.compatibility_status + ".</p><h3>Rolling event log</h3><div class='at-raw'>")
    for line:self.diagnostic_log webserver.content_send(line + "<br>") end
    webserver.content_send("</div><p><a href='/airthings_diagnostics'>Download diagnostics JSON</a></p></details></section>")

    webserver.content_send("<section class='at-card'><details><summary>Configuration backup and restore</summary><p><a href='/airthings_backup' target='_blank'>Download/copy configuration JSON</a></p><form id='at_restore' method='get' action='/airthings'><label>Paste configuration JSON</label><textarea id='at_config' name='config' rows='6' style='width:100%'></textarea><p id='at_preview' class='at-note'>Preview validates without changing settings.</p><button type='button' class='at-save' onclick='ap()'>Preview</button><button class='at-save' name='restore' value='1'>Apply restore</button></form><script>function ap(){fetch('/airthings_restore_preview?config='+encodeURIComponent(document.getElementById('at_config').value)).then(r=>r.json()).then(d=>document.getElementById('at_preview').textContent=(d.valid?'Valid: ':'Rejected: ')+d.message)}</script></details></section>")
    webserver.content_send("<section class='at-card'><details><summary>Home Assistant MQTT discovery</summary><form class='at-units' method='get' action='/airthings'><div><label>Discovery publishing</label><select name='discovery'>")
    if self.discovery_enabled webserver.content_send("<option value='0'>Disabled</option><option value='1' selected>Enabled</option>") else webserver.content_send("<option value='0' selected>Disabled</option><option value='1'>Enabled</option>") end
    webserver.content_send("</select></div><button class='at-save' name='setdiscovery' value='1'>Save and publish</button></form></details></section>")

    webserver.content_send("<section class='at-card'><details><summary>Pairing and discovered devices</summary><h3>Paired devices (maximum 2)</h3><table class='at-table'>")
    for i:0..size(self.paired_macs)-1
      var current = i == self.active_index ? "Active" : "<a href='/airthings?select=" + str(i) + "'>Select</a>"
      webserver.content_send("<tr><td><form method='get' action='/airthings'><input type='hidden' name='index' value='" + str(i) + "'><input name='device_name' value='" + self.paired_names[i] + "' style='max-width:150px'><button name='setname' value='1'>Save</button></form><span class='at-note'>" + self.paired_macs[i] + "</span></td><td>" + current + "</td><td><a href='/airthings?select=" + str(i) + "&unpair=1'>Remove</a></td></tr>")
    end
    webserver.content_send("</table><h3>Manual pair</h3><form class='at-pair' method='get' action='/airthings'>")
    webserver.content_send("<div class='at-field'><label>MAC address</label><input name='mac' value='" + self.mac_hex + "'></div>")
    webserver.content_send("<div class='at-field'><label>Type</label><input name='type' value='" + str(self.addr_type) + "' size='2'></div>")
    webserver.content_send("<button name='pair' value='1'>Pair</button>")
    webserver.content_send("</form>")

    webserver.content_send("<h3>Discovered devices</h3><div class='at-scroll'><table class='at-table'><tr><th>Serial</th><th>MAC</th><th>Type</th><th>RSSI</th><th></th></tr>")
    for i:0..size(self.dev_macs)-1
      webserver.content_send("<tr><td>" + self.dev_serials[i] + "</td><td>" + self.dev_macs[i] + "</td><td>" + str(self.dev_types[i]) + "</td><td>" + str(self.dev_rssi[i]) + "</td><td><a href='/airthings?pair=1&mac=" + self.dev_macs[i] + "&type=" + str(self.dev_types[i]) + "'>Pair</a></td></tr>")
    end
    webserver.content_send("</table></div></details></section>")
    webserver.content_send("</div>")
    webserver.content_button(webserver.BUTTON_MAIN)
    webserver.content_stop()
  end

  def row(name, value, unit)
    webserver.content_send("<tr><td>" + name + "</td><td><b>" + value + "</b></td><td>" + unit + "</td></tr>")
  end

  def row_id(id, name, value, unit)
    webserver.content_send("<tr><td>" + name + "</td><td><b id='at_" + id + "'>" + value + "</b></td><td>" + unit + "</td></tr>")
  end

  # ---------------------------------------------------------------------------
  # Periodic logic
  # ---------------------------------------------------------------------------
  def every_second()
    self.uptime_seconds += 1
    if self.seconds_since_read >= 0 self.seconds_since_read += 1 end
    if self.retry_wait > 0
      self.retry_wait -= 1
      if self.retry_wait == 0 && !self.read_active self.read_now() end
    end
    if self.scan_active
      self.scan_left -= 1
      if self.scan_left <= 0
        self.stop_scan()
        self.status = "Scan complete"
      end
    end

    if self.paired && !self.scan_active
      self.poll_count += 1
      if self.poll_count >= self.poll_seconds
        self.poll_count = 0
        self.next_device()
        self.read_now()
      end
    end
  end
end

airthings2930 = Airthings2930()
tasmota.add_driver(airthings2930)
