@echo off
REM ═══════════════════════════════════════════════════════════════════════
REM PUBLICAR LA WEB EN VERCEL (serviexpress.app) desde CMD — sin GitHub
REM Vercel descarga Flutter y compila en sus servidores (vercel.json).
REM Uso: doble clic en este archivo, o en CMD:  deploy_vercel.bat
REM Primera vez:  npm install -g vercel   y   vercel login
REM ═══════════════════════════════════════════════════════════════════════
cd /d "%~dp0"

REM Enlace con el proyecto "serviexpress" (lo crea Vercel la primera vez)
if not exist ".vercel\project.json" call vercel link --yes --project serviexpress

echo.
echo == Subiendo el codigo a Vercel. Vercel descarga Flutter y compila (5-10 min) ==
call vercel deploy --prod --yes
if errorlevel 1 (
  echo.
  echo ERROR: fallo la publicacion. Revisa el log en vercel.com
  pause
  exit /b 1
)

echo.
echo LISTO: https://serviexpress.app  y  https://serviexpress.app/form/
pause
