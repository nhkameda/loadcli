#!/usr/bin/env python3
"""Reduz e converte para WebP as ilustrações geradas pelo Nano Banana Pro.

O gerador devolve PNG de 2K com ~1,8 MB cada — bom para arquivar, inaceitável
para servir. Este script produz o `.webp` que o site usa e deixa o PNG original
de lado (fora do git, ver .gitignore).

    python3 tools/optimize-images.py

Requer Pillow (já instalado nesta máquina; o `sips` do macOS não faz WebP).
"""

import os
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("Falta o Pillow: pip3 install --user pillow")

ROOT = Path(__file__).resolve().parent.parent
IMG = ROOT / "assets" / "img"

# nome -> largura máxima servida
TARGETS = {
    "ritual": 1600,
    "spaces": 1600,
    "card": 1400,
    "footer": 1920,
    "og-en": 1200,
    "og-es": 1200,
    "og-zh": 1200,
    "og-pt": 1200,
}

total_before = total_after = 0

for name, width in TARGETS.items():
    src = IMG / f"{name}.png"
    if not src.exists():
        print(f"· {name}: sem PNG de origem, pulando")
        continue

    before = src.stat().st_size
    image = Image.open(src).convert("RGB")
    if image.width > width:
        height = round(image.height * width / image.width)
        image = image.resize((width, height), Image.LANCZOS)

    # O Open Graph precisa de PNG/JPEG: nem todo raspador lê WebP. JPEG porque
    # são degradês — em PNG cada card sairia com 700 KB.
    if name.startswith("og-"):
        out = IMG / f"{name}.jpg"
        image.save(out, "JPEG", quality=88, optimize=True, progressive=True)
        src.unlink(missing_ok=True)
    else:
        out = IMG / f"{name}.webp"
        image.save(out, "WEBP", quality=82, method=6)

    after = out.stat().st_size
    total_before += before
    total_after += after
    print(f"✓ {name}: {image.width}×{image.height} · {before // 1024} KB → {after // 1024} KB ({out.name})")

if total_before:
    print(f"\ntotal: {total_before // 1024} KB → {total_after // 1024} KB "
          f"({100 - round(total_after * 100 / total_before)}% menor)")
