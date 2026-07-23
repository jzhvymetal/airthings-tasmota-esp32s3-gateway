@echo off
setlocal
cd /d "%~dp0"
python "%~dp0airthings_workflow.py" %*
exit /b %errorlevel%
