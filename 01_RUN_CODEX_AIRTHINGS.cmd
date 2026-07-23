@echo off
setlocal
cd /d "%~dp0"
call airthings_with_codex.cmd
exit /b %errorlevel%

