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
   intended hub, and install the driver. `channel.json` contains a ready-to-use
   channel definition if the account does not have a private channel yet.
4. In the SmartThings app, scan for nearby devices. The driver discovers and
   verifies the `_airthings._tcp` service advertised by the ESP32.
5. Pull to refresh. One child device is created for every sensor returned by
   `http://<gateway-ip>/airthings_devices`.

The gateway IPv4 preference is optional and exists only as a fallback for
routers or VLANs that block multicast DNS. Automatic discovery stores the
address locally and follows future DHCP address changes after another scan.

The Edge refresh interval only reads cached values over the LAN. It does not
control the BLE polling interval configured on the Airthings web page.

SmartThings' standard Radon capability accepts only pCi/L. The driver converts
the gateway's canonical Bq/m3 values using `pCi/L = Bq/m3 / 37`.

## Development

Use `smartthings edge:drivers:logcat` while testing. The driver needs only local
LAN permission and does not require an MQTT broker, cloud service, Matter
commissioning, or custom SmartThings capabilities.
