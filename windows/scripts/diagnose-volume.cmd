@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnose-volume.ps1"
set "sideb_volume_exit=%ERRORLEVEL%"
echo.
pause
exit /b %sideb_volume_exit%
