"""
Crea versiones tablet de las capturas de pantalla para Play Store.
Target: 1200x1920 px (portrait 10"), fondo oscuro, imagen centrada.
Play Store requiere mínimo 1080px en el lado corto y ratio entre 1:2 y 2:1.

Ejecutar: doble clic en este archivo o desde terminal:
    python crear_tablet_screenshots.py
"""

import subprocess, sys

# Instalar Pillow si no está
try:
    from PIL import Image
except ImportError:
    print("Instalando Pillow...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "Pillow"])
    from PIL import Image

import os
from pathlib import Path

DOWNLOADS = Path.home() / "Downloads"
OUTPUT_DIR = DOWNLOADS / "tablet_screenshots"
OUTPUT_DIR.mkdir(exist_ok=True)

CANVAS_W = 1200
CANVAS_H = 1920
BG_COLOR = (18, 18, 18)  # fondo oscuro similar a la app

# Archivos a procesar (los que están en Downloads)
TARGETS = [
    "login.jpeg",
    "radar.jpeg",
    "card_servicio_movil.jpeg",
    "servicio_movil.jpeg",
    "vista_cliente.jpeg",
]

print(f"\nCreando capturas tablet en: {OUTPUT_DIR}\n")

procesados = 0
for nombre in TARGETS:
    src = DOWNLOADS / nombre
    if not src.exists():
        print(f"  [!] No encontrado: {nombre}")
        continue

    img = Image.open(src).convert("RGB")

    # Escalar para que quepa en el canvas manteniendo proporción
    ratio = min(CANVAS_W / img.width, CANVAS_H / img.height)
    new_w = int(img.width * ratio)
    new_h = int(img.height * ratio)
    img_scaled = img.resize((new_w, new_h), Image.LANCZOS)

    # Canvas con fondo oscuro
    canvas = Image.new("RGB", (CANVAS_W, CANVAS_H), BG_COLOR)

    # Centrar imagen en el canvas
    x = (CANVAS_W - new_w) // 2
    y = (CANVAS_H - new_h) // 2
    canvas.paste(img_scaled, (x, y))

    # Guardar
    stem = Path(nombre).stem
    out_path = OUTPUT_DIR / f"tablet_{stem}.jpg"
    canvas.save(out_path, "JPEG", quality=95)
    print(f"  OK  {out_path.name}  ({CANVAS_W}x{CANVAS_H})")
    procesados += 1

print(f"\nListo. {procesados} capturas guardadas en:\n{OUTPUT_DIR}")
input("\nPresiona Enter para cerrar...")
