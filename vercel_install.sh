#!/bin/bash
# Lo ejecuta VERCEL en sus servidores antes de compilar.
# Descarga Flutter (misma versión que se usaba en GitHub) y las dependencias.
set -e

FLUTTER_VERSION="3.44.6"

if [ ! -d "flutter" ]; then
  echo "== Descargando Flutter $FLUTTER_VERSION =="
  git clone https://github.com/flutter/flutter.git --depth 1 -b "$FLUTTER_VERSION" flutter
fi

export PATH="$PWD/flutter/bin:$PATH"
flutter config --enable-web --no-analytics
flutter --version
flutter pub get
