#!/usr/bin/env python3
"""MultiCAD - gera as texturas dos materiais (mapas de luminancia 64x64,
repetiveis) em data/textures/*.png e o include Pascal
src/ui/multicad_textures.inc usado pelo renderizador.
128 = neutro; o renderizador multiplica a cor do material por v/128."""
import os, numpy as np
from PIL import Image

N = 64
rng = np.random.default_rng(20261010)
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)

def periodic_noise(octaves, amp_decay=0.5, aniso=(1, 1)):
    """ruido repetivel somando senoides de frequencias inteiras"""
    y, x = np.mgrid[0:N, 0:N] / N
    out = np.zeros((N, N))
    a = 1.0
    for o in octaves:
        for _ in range(6):
            fx = rng.integers(1, o + 1) * aniso[0]
            fy = rng.integers(0, o + 1) * aniso[1]
            ph = rng.random() * 2 * np.pi
            out += a * np.sin(2 * np.pi * (fx * x + fy * y) + ph)
        a *= amp_decay
    out -= out.min(); out /= max(out.max(), 1e-9)
    return out

def white(sigma):
    w = rng.normal(0, sigma, (N, N))
    # suaviza 3x3 com envoltorio (repetivel)
    s = sum(np.roll(np.roll(w, i, 0), j, 1) for i in (-1, 0, 1) for j in (-1, 0, 1)) / 9
    return s

def to8(a, lo, hi):
    a = np.clip(a, 0, 1)
    return np.clip(lo + (hi - lo) * a, 0, 255).astype(np.uint8)

tex = {}
# aco: granulado fino
tex['steel'] = to8(0.5 + white(1.0) * 0.6, 118, 140)
# escovado: riscos ao longo de x
y = np.arange(N)
streak = np.tile(rng.normal(0, 1, (N, 1)), (1, N))
streak = (streak + np.roll(streak, 1, 0)) / 2
tex['brushed'] = to8(0.5 + streak * 0.18 + white(0.6) * 0.15, 100, 156)
# ferro fundido: manchado e aspero
tex['cast'] = to8(periodic_noise([4, 8, 16]) * 0.6 + 0.5 + white(1.5) * 0.4 - 0.3, 92, 160)
# plastico: quase liso
tex['plastic'] = to8(0.5 + white(0.5) * 0.25, 120, 136)
# borracha: fosco com granulado
tex['rubber'] = to8(0.5 + white(1.0) * 0.5, 112, 140)
# madeira: veios (aneis deformados) ao longo de x
yy, xx = np.mgrid[0:N, 0:N] / N
warp = periodic_noise([1, 2]) * 0.35
rings = 0.5 + 0.5 * np.sin(2 * np.pi * (7 * yy + warp))
grain = rings ** 3 * 0.75 + white(0.7) * 0.12 + periodic_noise([8], aniso=(0, 1)) * 0.15
tex['wood'] = to8(1 - grain, 82, 150)
tex['wood_dark'] = to8(1 - (rings ** 2) * 0.85 - white(0.8) * 0.1, 76, 148)
# compensado: faixas largas e suaves
tex['plywood'] = to8(0.55 + 0.35 * np.sin(2 * np.pi * (3 * yy + warp * 0.4)) + white(0.6) * 0.12, 98, 150)
# MDF: pontilhado fino uniforme
tex['mdf'] = to8(0.5 + white(1.6) * 0.45, 112, 142)
tex['plain'] = np.full((N, N), 128, np.uint8)

# escala: tamanho do ladrilho em mm
scale = {'steel': 6, 'brushed': 10, 'cast': 14, 'plastic': 8, 'rubber': 6,
         'wood': 40, 'wood_dark': 32, 'plywood': 50, 'mdf': 8, 'plain': 10}

order = ['plain', 'steel', 'brushed', 'cast', 'plastic', 'rubber', 'wood',
         'wood_dark', 'plywood', 'mdf']
os.makedirs(os.path.join(root, 'data', 'textures'), exist_ok=True)
for k in order:
    Image.fromarray(tex[k], 'L').save(os.path.join(root, 'data', 'textures', k + '.png'))

lines = ['{ Gerado por tools/gen_textures.py - nao edite a mao. }',
         'const',
         f'  CAD_TEX_SIZE = {N};',
         f'  CAD_TEX_COUNT = {len(order)};',
         '  CAD_TEX_NAMES: array[0..%d] of string = (%s);' % (len(order) - 1,
             ', '.join("'%s'" % k for k in order)),
         '  CAD_TEX_SCALE: array[0..%d] of Double = (%s);' % (len(order) - 1,
             ', '.join(str(float(scale[k])) for k in order)),
         '  CAD_TEX_DATA: array[0..%d, 0..%d] of Byte = (' % (len(order) - 1, N * N - 1)]
for ti, k in enumerate(order):
    flat = tex[k].flatten()
    rows = []
    for i in range(0, len(flat), 32):
        rows.append('    ' + ','.join(str(int(v)) for v in flat[i:i + 32]))
    lines.append('   (')
    lines.append(',\n'.join(rows))
    lines.append('   )' + (',' if ti < len(order) - 1 else ''))
lines.append('  );')
with open(os.path.join(root, 'src', 'ui', 'multicad_textures.inc'), 'w') as f:
    f.write('\n'.join(lines) + '\n')
print('ok', len(order))
