@echo off
setlocal
cd /d "%~dp0"
if "%~1"=="" (
  echo Usage: release.cmd VERSION "release notes" [--publish]
  echo Example: release.cmd 2.4.0 "Add health reporting and project automation" --publish
  exit /b 2
)
if "%~2"=="" (
  echo ERROR: Release notes are required.
  exit /b 2
)
python "%~dp0release.py" "%~1" --notes "%~2" %3
exit /b %errorlevel%
