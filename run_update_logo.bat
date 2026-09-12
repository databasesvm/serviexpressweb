@echo off
echo Actualizando logo de ServiExpress...
powershell -ExecutionPolicy Bypass -File "%~dp0update_logo.ps1"
pause
