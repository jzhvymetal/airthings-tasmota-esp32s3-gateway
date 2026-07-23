local Driver = require "st.driver"
local capabilities = require "st.capabilities"
local log = require "log"
local cosock = require "cosock"
local http = cosock.asyncify "socket.http"
local ltn12 = require "ltn12"
local json = require "dkjson"
local mdns = require "st.mdns"
local net_utils = require "st.net_utils"

local GATEWAY_PROFILE = "airthings-esp32-gateway"
local SENSOR_PROFILE = "airthings-wave-plus"
local MANAGER_DNI = "airthings-esp32-ble-gateway"
local EDGE_DRIVER_VERSION = "2.4.0"
local timer_by_device = {}

local function is_manager(device)
  return device.device_network_id:sub(1, #MANAGER_DNI) == MANAGER_DNI
end

local function number(value)
  local result = tonumber(value)
  if result == nil then return nil end
  return result
end

local function emit_if(device, capability, event)
  if event ~= nil and device:supports_capability(capability) then
    device:emit_event(event)
  end
end

local function emit_sensor(sensor, values)
  local temperature = number(values.temperature)
  local humidity = number(values.humidity)
  local pressure = number(values.pressure)
  local co2 = number(values.co2)
  local tvoc = number(values.voc)
  local light = number(values.light)
  local battery = number(values.battery)
  local radon_short = number(values.radon_short)
  local radon_long = number(values.radon_long)

  if temperature then emit_if(sensor, capabilities.temperatureMeasurement,
    capabilities.temperatureMeasurement.temperature({value=temperature, unit="C"})) end
  if humidity then emit_if(sensor, capabilities.relativeHumidityMeasurement,
    capabilities.relativeHumidityMeasurement.humidity(math.max(0, math.min(100, humidity)))) end
  if pressure then emit_if(sensor, capabilities.atmosphericPressureMeasurement,
    capabilities.atmosphericPressureMeasurement.atmosphericPressure({value=pressure / 10, unit="kPa"})) end
  if co2 then emit_if(sensor, capabilities.carbonDioxideMeasurement,
    capabilities.carbonDioxideMeasurement.carbonDioxide({value=co2, unit="ppm"})) end
  if tvoc then emit_if(sensor, capabilities.tvocMeasurement,
    capabilities.tvocMeasurement.tvocLevel({value=tvoc, unit="ppb"})) end
  if light then emit_if(sensor, capabilities.illuminanceMeasurement,
    capabilities.illuminanceMeasurement.illuminance(math.max(0, math.min(100000, light)))) end
  if battery then emit_if(sensor, capabilities.battery,
    capabilities.battery.battery(math.max(0, math.min(100, math.floor(battery + 0.5))))) end
  if radon_short then
    sensor:emit_component_event(sensor.profile.components.main,
      capabilities.radonMeasurement.radonLevel({value=radon_short / 37, unit="pCi/L"}))
  end
  if radon_long then
    sensor:emit_component_event(sensor.profile.components.longTermRadon,
      capabilities.radonMeasurement.radonLevel({value=radon_long / 37, unit="pCi/L"}))
  end
  if values.stale == true then sensor:offline() else sensor:online() end
end

local function find_sensor(driver, mac)
  for _, device in ipairs(driver:get_devices()) do
    if device.parent_assigned_child_key == mac then return device end
  end
  return nil
end

local function create_sensor(driver, manager, values)
  if not values.mac or find_sensor(driver, values.mac) then return end
  driver:try_create_device({
    type = "EDGE_CHILD",
    label = values.name or ("Airthings " .. values.mac),
    profile = SENSOR_PROFILE,
    parent_device_id = manager.id,
    parent_assigned_child_key = values.mac,
    vendor_provided_label = values.name or "Airthings Wave Plus",
    manufacturer = "Airthings",
    model = "Wave Plus 2930"
  })
end

local function fetch_ip(ip)
  local response = {}
  local _, status = http.request({
    url = "http://" .. ip .. "/airthings_devices",
    method = "GET",
    headers = {["Referer"] = "http://" .. ip .. "/"},
    sink = ltn12.sink.table(response)
  })
  if tonumber(status) ~= 200 then return nil, "HTTP status " .. tostring(status) end
  local data, _, err = json.decode(table.concat(response))
  if not data then return nil, err or "Invalid JSON" end
  return data, nil
end

local function gateway_ip(manager)
  local discovered = manager:get_field("gateway_ip")
  if discovered and discovered ~= "" then return discovered end
  local dni_ip = manager.device_network_id:match("|([%d%.]+)$")
  if dni_ip then return dni_ip end
  local configured = manager.preferences.gatewayIp
  if configured and configured ~= "" then return configured end
  return nil
end

local function fetch_gateway(manager)
  local ip = gateway_ip(manager)
  if not ip then return nil, "Gateway was not discovered and no fallback IP is configured" end
  return fetch_ip(ip)
end

local function refresh_gateway(driver, manager)
  local data, err = fetch_gateway(manager)
  if not data then
    log.warn("Airthings gateway refresh failed: " .. tostring(err))
    manager:offline()
    return
  end
  manager:online()
  manager:set_field("last_lan_refresh", os.date("!%Y-%m-%dT%H:%M:%SZ"), {persist=true})
  manager:set_field("gateway_driver_version", tostring(data.driver_version or "unknown"), {persist=true})
  manager:try_update_metadata({
    manufacturer = "Airthings Tasmota open-source gateway",
    model = "Berry " .. tostring(data.driver_version or "unknown") .. " / Edge " .. EDGE_DRIVER_VERSION,
    vendor_provided_label = "Airthings ESP32 Gateway"
  })
  for _, values in ipairs(data.devices or {}) do
    local sensor = find_sensor(driver, values.mac)
    if sensor then emit_sensor(sensor, values) else create_sensor(driver, manager, values) end
  end
end

local function schedule_refresh(driver, device)
  if timer_by_device[device.id] then device.thread:cancel_timer(timer_by_device[device.id]) end
  local interval = tonumber(device.preferences.refreshSeconds) or 60
  timer_by_device[device.id] = device.thread:call_on_schedule(interval, function()
    refresh_gateway(driver, device)
  end, "Airthings gateway refresh")
  device.thread:call_with_delay(1, function() refresh_gateway(driver, device) end)
end

local lifecycle = {}

function lifecycle.init(driver, device)
  if is_manager(device) then schedule_refresh(driver, device) end
end

function lifecycle.infoChanged(driver, device, event, args)
  if is_manager(device) then schedule_refresh(driver, device) end
end

function lifecycle.removed(_, device)
  if timer_by_device[device.id] then
    device.thread:cancel_timer(timer_by_device[device.id])
    timer_by_device[device.id] = nil
  end
end

local function discovery(driver)
  local manager = nil
  for _, device in ipairs(driver:get_devices()) do
    if is_manager(device) then manager = device end
  end
  local responses, err = mdns.discover("_airthings._tcp", "local")
  if not responses then
    log.warn("Airthings mDNS discovery failed: " .. tostring(err))
    return
  end
  for _, found in ipairs(responses.found or {}) do
    local ip = found.host_info and found.host_info.address
    if ip and net_utils.validate_ipv4_string(ip) then
      local data = fetch_ip(ip)
      if data and data.driver_version and data.devices then
        if manager then
          manager:set_field("gateway_ip", ip, {persist=true})
          manager:online()
          refresh_gateway(driver, manager)
        else
          driver:try_create_device({
            type = "LAN",
            device_network_id = MANAGER_DNI .. "|" .. ip,
            label = "Airthings ESP32 Gateway",
            profile = GATEWAY_PROFILE,
            manufacturer = "Airthings Tasmota open-source gateway",
            model = "Berry " .. tostring(data.driver_version) .. " / Edge " .. EDGE_DRIVER_VERSION,
            vendor_provided_label = "Airthings ESP32 Gateway"
          })
        end
        return
      end
    end
  end
  log.warn("No verified Airthings ESP32 gateway found by mDNS")
end

local function refresh_handler(driver, device)
  if is_manager(device) then
    refresh_gateway(driver, device)
  elseif device.parent_device_id then
    local parent = driver:get_device_info(device.parent_device_id)
    if parent then refresh_gateway(driver, parent) end
  end
end

local function health_ping_handler(driver, device)
  refresh_handler(driver, device)
end

local driver = Driver("airthings-esp32-ble-gateway", {
  discovery = discovery,
  lifecycle_handlers = lifecycle,
  supported_capabilities = {
    capabilities.temperatureMeasurement,
    capabilities.relativeHumidityMeasurement,
    capabilities.atmosphericPressureMeasurement,
    capabilities.carbonDioxideMeasurement,
    capabilities.tvocMeasurement,
    capabilities.illuminanceMeasurement,
    capabilities.battery,
    capabilities.radonMeasurement,
    capabilities.refresh,
    capabilities.healthCheck
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh_handler
    },
    [capabilities.healthCheck.ID] = {
      [capabilities.healthCheck.commands.ping.NAME] = health_ping_handler
    }
  }
})

driver:run()
