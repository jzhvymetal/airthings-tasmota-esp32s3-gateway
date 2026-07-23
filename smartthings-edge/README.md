# SmartThings Edge driver

This local LAN Edge driver connects a SmartThings-compatible hub directly to
the ESP32-S3 gateway. Matter is not used for sensor data. Each paired physical
Airthings monitor becomes one SmartThings child device containing temperature,
humidity, atmospheric pressure, CO2, TVOC, illuminance, battery, short-term
radon, and long-term radon.

## Install

1. Install the current SmartThings CLI and sign in.
2. Package the driver:

   `smartthings edge:drivers:package smartthings-edge`

3. Create or select a driver channel, assign the packaged driver, enroll the
   intended hub, and install the driver.
4. In the SmartThings app, scan for nearby devices. Open **Airthings ESP32
   Gateway**, set **Gateway IPv4 address** to the Tasmota address, and save.
5. Pull to refresh. One child device is created for every sensor returned by
   `http://<gateway-ip>/airthings_devices`.

The Edge refresh interval only reads cached values over the LAN. It does not
control the BLE polling interval configured on the Airthings web page.

## Development

Use `smartthings edge:drivers:logcat` while testing. The driver needs only local
LAN permission and does not require an MQTT broker, cloud service, Matter
commissioning, or custom SmartThings capabilities.
