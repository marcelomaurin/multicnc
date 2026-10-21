#!/usr/bin/env python3
"""Gera as imagens do instalador (welcome.bmp e slide0..6.bmp) a partir de imgs.

Equivalente ao prepare_images.ps1 para gerar o setup no Linux (Pillow).
Uso: python3 installer/windows/prepare_images.py [--version 0.15] [--out dist/installer-images]
"""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SLIDES = ["multicnc_novo_layout.png", "Makepcb01.png", "Makerouter01.png",
          "simucnc_router_ao_vivo.png", "Laserpcb01.png", "Laserart01.png", "ms_preview3d.png"]
FONTS = ["/usr/share/fonts/truetype/dejavu/DejaVuSans{}.ttf", "C:/Windows/Fonts/segoeui{}.ttf"]


def font(size, bold=False):
    for pattern in FONTS:
        path = Path(pattern.format("-Bold" if bold and "dejavu" in pattern else ("b" if bold else "")))
        if path.is_file():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


def make(source, destination, width, height, heading="", subheading=""):
    original = Image.open(ROOT / "imgs" / source).convert("RGB")
    canvas = Image.new("RGB", (width, height), (23, 36, 54))
    top = 8
    if heading:
        draw = ImageDraw.Draw(canvas)
        draw.text((12, 16), heading, font=font(15, True), fill="white")
        y = 82
        for line in subheading.split(". "):
            draw.text((12, y), line.strip(), font=font(12), fill="white")
            y += 18
        top = 180
    scale = min((width - 16) / original.width, (height - top - 8) / original.height)
    w, h = int(original.width * scale), int(original.height * scale)
    canvas.paste(original.resize((w, h), Image.LANCZOS), ((width - w) // 2, int(top + (height - top - h) / 2)))
    canvas.save(destination, "BMP")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="0.15")
    parser.add_argument("--out", type=Path, default=ROOT / "dist" / "installer-images")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    make("tres_maquinas_3d.png", args.out / "welcome.bmp", 246, 471,
         f"MultiSuite {args.version}", "Projetar, preparar, simular e fabricar.")
    for index, name in enumerate(SLIDES):
        make(name, args.out / f"slide{index}.bmp", 900, 350)
    print("imagens em", args.out)


if __name__ == "__main__":
    main()
