@echo off
setlocal
cd /d "%~dp0"
echo Packaging and installing the Airthings SmartThings Edge driver...
echo The SmartThings CLI will ask you to sign in and select a channel and hub.
call npx --yes @smartthings/cli edge:drivers:package smartthings-edge --install
if errorlevel 1 (
  echo.
  echo Edge driver installation failed. Review the CLI message above.
  exit /b 1
)
echo.
echo Driver installed. In SmartThings, scan for nearby devices and configure
echo the Gateway IPv4 address in the Airthings ESP32 Gateway settings.
endlocal
