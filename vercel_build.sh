#!/bin/bash
# Lo ejecuta VERCEL en sus servidores: compila las DOS versiones de la web.
#   serviexpress.app/       → operadores (login)
#   serviexpress.app/form/  → invitados (la app detecta '/form' en la URL)
set -e
export PATH="$PWD/flutter/bin:$PATH"

rm -rf deploy_vercel
mkdir -p deploy_vercel/form

echo "== Compilando OPERADORES (/) =="
flutter build web --release --base-href "/"
cp -r build/web/. deploy_vercel/

echo "== Compilando INVITADOS (/form/) =="
flutter build web --release --base-href "/form/"
cp -r build/web/. deploy_vercel/form/

echo "== Listo =="
