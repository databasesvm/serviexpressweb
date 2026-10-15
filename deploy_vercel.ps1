# ═══════════════════════════════════════════════════════════════════════════
# PUBLICAR LA WEB EN VERCEL (serviexpress.app) — sin GitHub
#
# Sube el código a Vercel y VERCEL COMPILA CON FLUTTER en sus servidores
# (vercel.json → vercel_install.sh + vercel_build.sh). Quedan:
#   • serviexpress.app/       → operadores (login)
#   • serviexpress.app/form/  → invitados (pedir sin registrarse)
#
# Uso (en PowerShell, dentro de la carpeta del proyecto):
#   .\deploy_vercel.ps1
#
# Requisitos (solo la primera vez):
#   1) Node.js instalado  → https://nodejs.org
#   2) npm install -g vercel
#   3) vercel login        (entra con la cuenta databasesvm@gmail.com)
# ═══════════════════════════════════════════════════════════════════════════

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# Enlace con el proyecto "serviexpress" de Vercel (lo crea Vercel la 1ra vez)
if (-not (Test-Path (Join-Path $PSScriptRoot '.vercel\project.json'))) {
  vercel link --yes --project serviexpress
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo enlazar con el proyecto serviexpress' }
}

Write-Host ''
Write-Host '== Subiendo el codigo a Vercel. Vercel descarga Flutter y compila (5-10 min) ==' -ForegroundColor Green
vercel deploy --prod --yes
if ($LASTEXITCODE -ne 0) { throw 'Fallo la publicacion en Vercel (revisa el log en vercel.com)' }

Write-Host ''
Write-Host 'LISTO: https://serviexpress.app  y  https://serviexpress.app/form/' -ForegroundColor Green
