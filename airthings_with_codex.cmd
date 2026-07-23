@echo off
setlocal

rem Run from the folder containing this batch file
cd /d "%~dp0"

if not exist "CODEX_PROMPT_AIRTHINGS_CONTINUE.md" (
    echo ERROR: CODEX_PROMPT_AIRTHINGS_CONTINUE.md was not found.
    echo Current directory: %CD%
    pause
    exit /b 1
)

if not exist "airthings_settings.ini" (
    echo ERROR: airthings_settings.ini was not found.
    echo Current directory: %CD%
    pause
    exit /b 1
)

(
    type "CODEX_PROMPT_AIRTHINGS_CONTINUE.md"
    echo.
    echo Read and follow all instructions above completely.
    echo Use airthings_settings.ini for configuration.
    echo Run the requested Airthings workflow and modify files as needed.
    echo Continue until verification passes or a concrete hardware or credential blocker is proven.
) | codex.cmd ^
    --ask-for-approval never ^
    --sandbox danger-full-access ^
    --cd . ^
    exec ^
    --skip-git-repo-check ^
    -

set "RESULT=%ERRORLEVEL%"

echo.
echo Codex finished with exit code %RESULT%.
pause
exit /b %RESULT%