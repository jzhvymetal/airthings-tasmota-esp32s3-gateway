# SmartThings Edge driver

This local LAN Edge driver connects a SmartThings-compatible hub directly to
the ESP32-S3 gateway. Matter is not used for sensor data. Each paired physical
Airthings monitor becomes one SmartThings child device containing temperature,
humidity, atmospheric pressure, CO2, TVOC, illuminance, battery, short-term
radon, and long-term radon.

## Install

1. Open the
   [Airthings ESP32 Gateway channel invitation](https://bestow-regional.api.smartthings.com/invite/1J2QymxnWw20)
   and sign in with the Samsung account that owns the SmartThings hub.
2. Accept the invitation and enroll the intended hub.
3. Select **Available Drivers**, select **Airthings ESP32 Gateway**, and install
   it on the hub.
4. In the SmartThings app, choose **Add device** and **Scan nearby**. The driver
   discovers and verifies the `_airthings._tcp` service advertised by the
   ESP32.
5. Pull to refresh. One child device is created for every sensor returned by
   `http://<gateway-ip>/airthings_devices`.

The invitation installs the already-published driver; other users do not need
the SmartThings CLI, the ESP32 address, or access to the source repository.

## Developer installation

To package and publish changes from the source, run
`smartthings_edge_install.cmd`, sign in through the SmartThings CLI, and select
the intended driver channel and hub. `channel.json` contains a ready-to-use
channel definition if the account does not have a private channel yet.

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
