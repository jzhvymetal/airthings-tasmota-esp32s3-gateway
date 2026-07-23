@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ==============================================================================
REM Airthings / Tasmota ESP32-S3-N16R8 Codex-Controlled Build + Flash + Serial Test
REM
REM This version uses the folder where this .cmd file is located as the root folder.
REM No hard-coded C:\TEMP path is used.
REM
REM Folder layout:
REM   <root>\airthings_codex_usb_full.cmd
REM   <root>\airthings_serial_verify.py
REM   <root>\Tasmota\
REM   <root>\airthings_tasmota_logs\
REM
REM Commands:
REM   airthings_codex_usb_full.cmd all COM7
REM   airthings_codex_usb_full.cmd build
REM   airthings_codex_usb_full.cmd build tasmota32s3-mi32-test
REM   airthings_codex_usb_full.cmd flash COM7
REM   airthings_codex_usb_full.cmd test COM7
REM   airthings_codex_usb_full.cmd clean
REM
REM Optional:
REM   airthings_codex_usb_full.cmd all COM7 tasmota32s3-airthings-mi32-matter 12
REM ==============================================================================

set "ROOT_DIR=%~dp0"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"

set "WORKING_DIR=%ROOT_DIR%"
set "TASMOTA_DIR=%ROOT_DIR%\Tasmota"
set "LOG_DIR=%ROOT_DIR%\airthings_tasmota_logs"
set "PY_VERIFY=%ROOT_DIR%\airthings_serial_verify.py"

set "ENV_DEFAULT=tasmota32s3-airthings-mi32-matter"
set "ENV_TEST=tasmota32s3-mi32-test"

set "ACTION=%~1"
if "%ACTION%"=="" set "ACTION=all"

set "PORT="
set "ENV_NAME=%ENV_DEFAULT%"
set "JOBS=8"

if /I "%ACTION%"=="all" (
    set "PORT=%~2"
    if not "%~3"=="" set "ENV_NAME=%~3"
    if not "%~4"=="" set "JOBS=%~4"
)

if /I "%ACTION%"=="flash" (
    set "PORT=%~2"
    if not "%~3"=="" set "ENV_NAME=%~3"
)

if /I "%ACTION%"=="test" (
    set "PORT=%~2"
    if not "%~3"=="" set "ENV_NAME=%~3"
)

if /I "%ACTION%"=="build" (
    if not "%~2"=="" set "ENV_NAME=%~2"
    if not "%~3"=="" set "JOBS=%~3"
)

if /I "%ACTION%"=="setup" (
    if not "%~2"=="" set "ENV_NAME=%~2"
)

if /I "%ACTION%"=="clean" (
    if not "%~2"=="" set "ENV_NAME=%~2"
)

set "INI_FILE=%TASMOTA_DIR%\platformio_tasmota_cenv.ini"
set "OVERRIDE_H=%TASMOTA_DIR%\tasmota\user_config_override.h"

for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "TS=%%I"

echo.
echo ============================================================
echo AIRTHINGS TASMOTA CODEX USB BUILD/FLASH/TEST
echo ============================================================
echo Action:      %ACTION%
echo Root dir:    %ROOT_DIR%
echo Port:        %PORT%
echo Build env:   %ENV_NAME%
echo Jobs:        %JOBS%
echo Tasmota dir: %TASMOTA_DIR%
echo Logs:        %LOG_DIR%
echo ============================================================
echo.

if /I "%ACTION%"=="setup" goto :setup_only
if /I "%ACTION%"=="clean" goto :clean_only
if /I "%ACTION%"=="build" goto :build_only
if /I "%ACTION%"=="flash" goto :flash_only
if /I "%ACTION%"=="test" goto :test_only
if /I "%ACTION%"=="all" goto :all_steps

echo ERROR: Unknown action "%ACTION%".
echo Valid actions: setup, clean, build, flash, test, all
goto :error

:all_steps
call :setup || goto :error
call :clean || goto :error
call :build || goto :error
call :flash || goto :error
call :test || goto :error
goto :done

:setup_only
call :setup || goto :error
goto :done

:clean_only
call :setup || goto :error
call :clean || goto :error
goto :done

:build_only
call :setup || goto :error
call :build || goto :error
goto :done

:flash_only
call :setup || goto :error
call :flash || goto :error
goto :done

:test_only
call :setup || goto :error
call :test || goto :error
goto :done

:setup
echo [SETUP] Checking tools...

where docker >nul 2>&1
if errorlevel 1 (
    echo ERROR: Docker was not found in PATH. Install/start Docker Desktop.
    exit /b 1
)

where git >nul 2>&1
if errorlevel 1 (
    echo ERROR: Git was not found in PATH. Install Git for Windows.
    exit /b 1
)

where python >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python was not found in PATH. Install Python 3.
    exit /b 1
)

if not exist "%WORKING_DIR%" mkdir "%WORKING_DIR%"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

if not exist "%PY_VERIFY%" (
    echo ERROR: Python verifier not found:
    echo   %PY_VERIFY%
    echo Keep airthings_serial_verify.py in the same folder as this .cmd file.
    exit /b 1
)

echo [SETUP] Installing required Python packages...
python -m pip install --upgrade pyserial esptool > "%LOG_DIR%\pip_%TS%.log" 2>&1
if errorlevel 1 (
    type "%LOG_DIR%\pip_%TS%.log"
    echo ERROR: pip install failed.
    exit /b 1
)

if not exist "%TASMOTA_DIR%\platformio.ini" (
    echo [SETUP] Tasmota source not found. Cloning into:
    echo   %TASMOTA_DIR%
    if exist "%TASMOTA_DIR%" rmdir /s /q "%TASMOTA_DIR%"
    cd /d "%WORKING_DIR%"
    git clone "https://github.com/arendst/Tasmota.git" "%TASMOTA_DIR%"
    if errorlevel 1 (
        echo ERROR: Git clone failed.
        exit /b 1
    )
) else (
    echo [SETUP] Existing Tasmota source found.
)

cd /d "%TASMOTA_DIR%"
if errorlevel 1 (
    echo ERROR: Could not enter Tasmota folder.
    exit /b 1
)

echo [SETUP] Pulling Docker image...
docker pull blakadder/docker-tasmota
if errorlevel 1 (
    echo ERROR: Docker pull failed.
    exit /b 1
)

echo [SETUP] Writing runtime feature defaults...
call :write_user_config_override || exit /b 1

echo [SETUP] Writing PlatformIO custom environments...
call :write_ini || exit /b 1

echo [SETUP] Writing Codex notes...
call :write_codex_notes || exit /b 1

exit /b 0

:clean
echo [CLEAN] Removing local build folders...
if exist "%TASMOTA_DIR%\.pio" rmdir /s /q "%TASMOTA_DIR%\.pio"
if exist "%TASMOTA_DIR%\build_output" rmdir /s /q "%TASMOTA_DIR%\build_output"

echo [CLEAN] Resetting Docker PlatformIO cache volume...
docker container prune -f
docker volume rm pio_cache -f >nul 2>&1
docker volume create pio_cache
if errorlevel 1 (
    echo ERROR: Could not create Docker volume pio_cache.
    exit /b 1
)

exit /b 0

:build
cd /d "%TASMOTA_DIR%"

set "BUILD_LOG=%LOG_DIR%\build_%ENV_NAME%_%TS%.log"
echo [BUILD] Compiling with Docker/PlatformIO...
echo [BUILD] Log: %BUILD_LOG%
echo.

docker run --rm ^
  -v pio_cache:/root/.platformio ^
  -v "%TASMOTA_DIR%:/tasmota" ^
  --entrypoint bash ^
  blakadder/docker-tasmota ^
  -lc "cd /tasmota && pio run -e %ENV_NAME% -j %JOBS%" > "%BUILD_LOG%" 2>&1

set "BUILD_RC=%ERRORLEVEL%"
type "%BUILD_LOG%"

if not "%BUILD_RC%"=="0" (
    echo ERROR: Build failed with exit code %BUILD_RC%.
    echo Log saved to: %BUILD_LOG%
    exit /b %BUILD_RC%
)

call :copy_and_verify_firmware || exit /b 1
exit /b 0

:flash
if "%PORT%"=="" (
    echo ERROR: Flash requires a COM port.
    echo Example: %~nx0 flash COM7
    exit /b 1
)

call :copy_and_verify_firmware || exit /b 1

set "FIRMWARE=%TASMOTA_DIR%\.pio\build\%ENV_NAME%\firmware.factory.bin"

echo.
echo [FLASH] Erasing ESP32-S3 on %PORT%...
python -m esptool --chip esp32s3 --port %PORT% erase_flash
if errorlevel 1 (
    echo ERROR: erase_flash failed.
    exit /b 1
)

echo.
echo [FLASH] Flashing/downloading firmware to ESP32-S3...
python -m esptool --chip esp32s3 --port %PORT% --baud 921600 write_flash -z 0x0 "%FIRMWARE%"
if errorlevel 1 (
    echo ERROR: Flash failed at 921600. Retrying at 460800...
    python -m esptool --chip esp32s3 --port %PORT% --baud 460800 write_flash -z 0x0 "%FIRMWARE%"
    if errorlevel 1 (
        echo ERROR: Flash failed at 460800 too.
        exit /b 1
    )
)

echo [FLASH] Done.
exit /b 0

:test
if "%PORT%"=="" (
    echo ERROR: Test requires a COM port.
    echo Example: %~nx0 test COM7
    exit /b 1
)

set "TEST_LOG=%LOG_DIR%\serial_test_%ENV_NAME%_%TS%.log"

echo.
echo [TEST] Checking Tasmota serial console on %PORT%...
echo [TEST] Log: %TEST_LOG%
echo.

python "%PY_VERIFY%" ^
  --port "%PORT%" ^
  --baud 115200 ^
  --boot-wait 25 ^
  --log "%TEST_LOG%" ^
  --command "Br import MI32; print('MI32 OK')" --expect "MI32 OK" ^
  --command "Br import BLE; print('BLE OK')" --expect "BLE OK" ^
  --command "MtrInfo" --expect "MtrInfo"

set "TEST_RC=%ERRORLEVEL%"

if exist "%TEST_LOG%" type "%TEST_LOG%"

if not "%TEST_RC%"=="0" (
    echo.
    echo ERROR: Serial command verification failed.
    echo Log saved to: %TEST_LOG%
    exit /b %TEST_RC%
)

echo.
echo [TEST] Serial verification passed.
exit /b 0

:write_ini
> "%INI_FILE%" echo ; Auto-generated by airthings_codex_usb_full.cmd
>> "%INI_FILE%" echo ; Root: %ROOT_DIR%
>> "%INI_FILE%" echo ; Target: ESP32-S3-N16R8, QIO Flash / OPI PSRAM
>> "%INI_FILE%" echo.
>> "%INI_FILE%" echo [env:%ENV_TEST%]
>> "%INI_FILE%" echo extends                 = env:tasmota32_base
>> "%INI_FILE%" echo board                   = esp32s3-qio_opi
>> "%INI_FILE%" echo board_build.f_cpu       = 240000000L
>> "%INI_FILE%" echo board_build.f_flash     = 80000000L
>> "%INI_FILE%" echo board_build.flash_mode  = qio
>> "%INI_FILE%" echo board_upload.flash_size = 16MB
>> "%INI_FILE%" echo lib_ignore              = Micro-RTSP
>> "%INI_FILE%" echo build_flags             = ${env:tasmota32_base.build_flags}
>> "%INI_FILE%" echo                           -DFIRMWARE_BLUETOOTH
>> "%INI_FILE%" echo                           -DUSE_MI_ESP32
>> "%INI_FILE%" echo                           -DUSE_MI_EXT_GUI
>> "%INI_FILE%" echo                           -DBLE_ESP32_ENABLE=true
>> "%INI_FILE%" echo                           -DCONFIG_BT_NIMBLE_NVS_PERSIST=y
>> "%INI_FILE%" echo                           -DOTA_URL='""'
>> "%INI_FILE%" echo lib_extra_dirs          = lib/libesp32, lib/libesp32_div, lib/lib_basic, lib/lib_i2c, lib/lib_div, lib/lib_ssl, lib/lib_rf
>> "%INI_FILE%" echo.
>> "%INI_FILE%" echo [env:%ENV_DEFAULT%]
>> "%INI_FILE%" echo extends                 = env:%ENV_TEST%
>> "%INI_FILE%" echo build_flags             = ${env:%ENV_TEST%.build_flags}
>> "%INI_FILE%" echo                           -DUSE_MATTER_DEVICE
>> "%INI_FILE%" echo                           -DMATTER_ENABLED=true
>> "%INI_FILE%" echo                           -DUSE_UFILESYS
exit /b 0

:write_user_config_override
> "%OVERRIDE_H%" echo #ifndef _USER_CONFIG_OVERRIDE_H_
>> "%OVERRIDE_H%" echo #define _USER_CONFIG_OVERRIDE_H_
>> "%OVERRIDE_H%" echo #undef BLE_ESP32_ENABLE
>> "%OVERRIDE_H%" echo #define BLE_ESP32_ENABLE true
>> "%OVERRIDE_H%" echo #undef MATTER_ENABLED
>> "%OVERRIDE_H%" echo #define MATTER_ENABLED true
>> "%OVERRIDE_H%" echo #endif
exit /b 0

:write_codex_notes
set "TASK_FILE=%TASMOTA_DIR%\CODEX_TASK.md"
> "%TASK_FILE%" echo # Codex task: Tasmota ESP32-S3 Airthings MI32 + Matter
>> "%TASK_FILE%" echo.
>> "%TASK_FILE%" echo Root folder:
>> "%TASK_FILE%" echo.
>> "%TASK_FILE%" echo ```text
>> "%TASK_FILE%" echo %ROOT_DIR%
>> "%TASK_FILE%" echo ```
>> "%TASK_FILE%" echo.
>> "%TASK_FILE%" echo Goal: build and iterate firmware for ESP32-S3-N16R8 that supports Tasmota Berry, MI32 legacy BLE modules, Matter, and Airthings BLE GATT reading.
>> "%TASK_FILE%" echo.
>> "%TASK_FILE%" echo Acceptance tests:
>> "%TASK_FILE%" echo.
>> "%TASK_FILE%" echo ```text
>> "%TASK_FILE%" echo Br import MI32; print("MI32 OK"^)
>> "%TASK_FILE%" echo Br import BLE; print("BLE OK"^)
>> "%TASK_FILE%" echo MtrInfo
>> "%TASK_FILE%" echo ```
>> "%TASK_FILE%" echo.
>> "%TASK_FILE%" echo Expected:
>> "%TASK_FILE%" echo - MI32 OK
>> "%TASK_FILE%" echo - BLE OK
>> "%TASK_FILE%" echo - MtrInfo response, not Unknown command
>> "%TASK_FILE%" echo.
>> "%TASK_FILE%" echo Logs:
>> "%TASK_FILE%" echo.
>> "%TASK_FILE%" echo ```text
>> "%TASK_FILE%" echo %LOG_DIR%
>> "%TASK_FILE%" echo ```
exit /b 0

:copy_and_verify_firmware
set "BUILD_DIR=%TASMOTA_DIR%\.pio\build\%ENV_NAME%"
set "OUT_DIR=%TASMOTA_DIR%\build_output\firmware"
set "FIRMWARE=%BUILD_DIR%\firmware.factory.bin"

if not exist "%FIRMWARE%" (
    echo ERROR: Factory firmware was not found:
    echo   %FIRMWARE%
    exit /b 1
)

powershell -NoProfile -Command "$p='%FIRMWARE%'; $b=[IO.File]::ReadAllBytes($p); if ($b.Length -lt 1024) { Write-Host 'ERROR: firmware is too small'; exit 2 }; if ($b[0] -ne 0xE9) { Write-Host ('ERROR: invalid firmware header 0x{0:X2}' -f $b[0]); exit 3 }; Write-Host ('Firmware header OK. Size: {0:N0} bytes' -f $b.Length)"
if errorlevel 1 exit /b 1

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

copy /Y "%FIRMWARE%" "%OUT_DIR%\%ENV_NAME%.factory.bin" >nul

if exist "%BUILD_DIR%\firmware.bin" (
    copy /Y "%BUILD_DIR%\firmware.bin" "%OUT_DIR%\%ENV_NAME%.bin" >nul
)

echo.
echo Firmware:
echo   %FIRMWARE%
echo Copy:
echo   %OUT_DIR%\%ENV_NAME%.factory.bin
echo.
exit /b 0

:done
echo.
echo ============================================================
echo DONE
echo ============================================================
echo Logs:
echo   %LOG_DIR%
echo Firmware:
echo   %TASMOTA_DIR%\.pio\build\%ENV_NAME%\firmware.factory.bin
echo.
if not defined AIRTHINGS_NO_PAUSE pause
exit /b 0

:error
echo.
echo ============================================================
echo FAILED
echo ============================================================
echo Check the log files in:
echo   %LOG_DIR%
echo.
if not defined AIRTHINGS_NO_PAUSE pause
exit /b 1
