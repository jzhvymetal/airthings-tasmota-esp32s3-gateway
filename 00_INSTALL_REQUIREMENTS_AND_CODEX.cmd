@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT_DIR=%~dp0"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"
set "LOG_DIR=%ROOT_DIR%\airthings_tasmota_logs"

echo ============================================================
echo AIRTHINGS CODEX COMMISSIONING - REQUIREMENTS INSTALLER
echo ============================================================
echo Root folder:
echo   %ROOT_DIR%
echo.

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

echo This installs/checks:
echo   Docker Desktop
echo   Git for Windows
echo   Python 3
echo   Node.js LTS
echo   OpenAI Codex CLI
echo   Python packages: pyserial, esptool
echo.

where winget >nul 2>&1
if errorlevel 1 (
    echo ERROR: winget was not found.
    echo Install these manually:
    echo   Docker Desktop, Git for Windows, Python 3, Node.js LTS
    goto :error
)

echo.
echo Installing/checking Git...
winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements

echo.
echo Installing/checking Python...
winget install --id Python.Python.3.12 -e --accept-package-agreements --accept-source-agreements

echo.
echo Installing/checking Node.js LTS...
winget install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements

echo.
echo Installing/checking Docker Desktop...
winget install --id Docker.DockerDesktop -e --accept-package-agreements --accept-source-agreements

echo.
echo Refreshing PATH for this session...
set "PATH=%PATH%;%ProgramFiles%\Git\cmd;%LocalAppData%\Programs\Python\Python312;%LocalAppData%\Programs\Python\Python312\Scripts;%ProgramFiles%\nodejs;%AppData%\npm"

echo.
echo Installing Python serial/flash tools...
python -m pip install --upgrade pip
python -m pip install --upgrade pyserial esptool

echo.
echo Installing OpenAI Codex CLI with npm...
where npm >nul 2>&1
if errorlevel 1 (
    echo ERROR: npm was not found. Close and reopen Command Prompt, then rerun this script.
    goto :error
)
npm install -g @openai/codex

echo.
echo Checking versions...
git --version
python --version
npm --version
codex.cmd --version

echo.
echo Starting Docker Desktop if installed...
if exist "%ProgramFiles%\Docker\Docker\Docker Desktop.exe" (
    start "" "%ProgramFiles%\Docker\Docker\Docker Desktop.exe"
)

echo.
echo Waiting up to 120 seconds for Docker engine...
set /a COUNT=0
:docker_wait
docker info >nul 2>&1
if not errorlevel 1 goto :docker_ready
set /a COUNT+=1
if %COUNT% GEQ 24 (
    echo WARNING: Docker is not ready yet.
    echo Open Docker Desktop and wait until it says it is running, then continue.
    goto :after_docker
)
timeout /t 5 /nobreak >nul
goto :docker_wait

:docker_ready
echo Docker is ready.
docker pull blakadder/docker-tasmota

:after_docker
echo.
echo ============================================================
echo REQUIREMENTS STEP COMPLETE
echo ============================================================
echo.
echo Next:
echo   1. Sign into Codex:
echo        codex.cmd login
echo.
echo   2. Run:
echo        "%ROOT_DIR%\01_RUN_CODEX_AIRTHINGS.cmd"
echo.
pause
exit /b 0

:error
echo.
echo ============================================================
echo REQUIREMENTS STEP FAILED
echo ============================================================
pause
exit /b 1
