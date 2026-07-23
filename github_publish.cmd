@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
set "DEFAULT_REPOSITORY_URL=https://github.com/jzhvymetal/airthings-tasmota-esp32s3-gateway.git"

echo.
echo Airthings GitHub Publisher
echo ==========================
echo Private settings, build output, logs, Tasmota sources, and firmware
echo binaries are excluded from publication.
echo.

where git >nul 2>&1
if errorlevel 1 (
  echo ERROR: Git is not installed or is not available in PATH.
  echo Install Git for Windows from https://git-scm.com/download/win
  exit /b 1
)

if not exist ".gitignore" (
  echo ERROR: .gitignore is missing. Publishing stopped to protect private data.
  exit /b 1
)

git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
  echo Initializing local Git repository...
  git init
  if errorlevel 1 goto :failed
)

git check-ignore -q "airthings_settings.ini"
if errorlevel 1 (
  echo ERROR: airthings_settings.ini is not ignored. Publishing stopped.
  exit /b 1
)

if not exist "airthings_settings.example.ini" (
  echo ERROR: airthings_settings.example.ini is missing.
  exit /b 1
)

git branch -M main
if errorlevel 1 goto :failed

git config user.name >nul 2>&1
if errorlevel 1 (
  set /p "GIT_NAME=Git author name: "
  if not defined GIT_NAME (
    echo ERROR: An author name is required.
    exit /b 1
  )
  git config user.name "!GIT_NAME!"
)

git config user.email >nul 2>&1
if errorlevel 1 (
  set /p "GIT_EMAIL=Git author email: "
  if not defined GIT_EMAIL (
    echo ERROR: An author email is required.
    exit /b 1
  )
  git config user.email "!GIT_EMAIL!"
)

echo Staging publishable files...
git add .
if errorlevel 1 goto :failed

git diff --cached --name-only | findstr /x /i "airthings_settings.ini" >nul
if not errorlevel 1 (
  git restore --staged "airthings_settings.ini" >nul 2>&1
  echo ERROR: Private airthings_settings.ini was staged and has been unstaged.
  exit /b 1
)

echo.
echo Files ready for publication:
git diff --cached --name-only
echo.

git diff --cached --quiet
if errorlevel 1 (
  set "COMMIT_MESSAGE="
  set /p "COMMIT_MESSAGE=Commit message [Airthings Tasmota release]: "
  if not defined COMMIT_MESSAGE set "COMMIT_MESSAGE=Airthings Tasmota release"
  git commit -m "!COMMIT_MESSAGE!"
  if errorlevel 1 goto :failed
) else (
  echo No new local changes need to be committed.
)

git remote get-url origin >nul 2>&1
if errorlevel 1 (
  echo.
  echo Default repository: !DEFAULT_REPOSITORY_URL!
  set "REPOSITORY_URL="
  set /p "REPOSITORY_URL=Repository URL [press Enter for default]: "
  if not defined REPOSITORY_URL set "REPOSITORY_URL=!DEFAULT_REPOSITORY_URL!"
  echo !REPOSITORY_URL! | findstr /i /r /c:"^https://github.com/" /c:"^git@github.com:" >nul
  if errorlevel 1 (
    echo ERROR: Expected an HTTPS or SSH github.com repository URL.
    exit /b 1
  )
  git remote add origin "!REPOSITORY_URL!"
  if errorlevel 1 goto :failed
) else (
  for /f "delims=" %%U in ('git remote get-url origin') do set "REPOSITORY_URL=%%U"
  echo Using existing origin: !REPOSITORY_URL!
)

echo.
echo Pushing main branch to GitHub...
git push -u origin main
if errorlevel 1 (
  echo.
  echo Push failed. Complete GitHub authentication if prompted, verify that
  echo the repository is empty and that you have access, then run this file again.
  exit /b 1
)

echo.
echo SUCCESS: The repository was published to:
git remote get-url origin
echo.
pause
exit /b 0

:failed
echo.
echo ERROR: Git returned an error. Nothing was force-pushed or deleted.
exit /b 1
