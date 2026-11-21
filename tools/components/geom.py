"""Primitivas de geometria para a biblioteca de componentes do MultiAssembly.

Cada componente recebe um bloco ``geometry`` (lista de primitivas em mm, no
sistema local da peça).  O gerador calcula a caixa envolvente, desloca tudo
para que o canto mínimo fique em (0, 0, 0) e grava ``size`` a partir dela.

Eixos das primitivas (mapeamento cíclico, mão direita):
    axis "z": u -> X, v -> Y, w (extrusão) -> Z
    axis "x": u -> Y, v -> Z, w -> X
    axis "y": u -> Z, v -> X, w -> Y

Tipos:
    box    {at:[x,y,z], size:[sx,sy,sz]}
    cyl    {axis, at: centro da base, r, h, ri?, r2?, seg?, rot?, arc?, caps?}
    prism  {axis, at: origem do polígono, h, poly:[[u,v],...]}
    disk   {axis, at: centro, r, seg?, rot?}  -> decalque (furo, LED, etiqueta);
           não entra na caixa envolvente e é desenhado sobre a face.
"""

import math

# ---------------------------------------------------------------- cores (RGB)
ALU = 0xC9CDD2          # alumínio anodizado natural
ALU_DARK = 0x9EA4AC     # alumínio fundido / jateado
ALU_BLACK = 0x2B2D31    # alumínio anodizado preto
STEEL = 0xB4B9C0        # aço usinado
CHROME = 0xDDE1E6       # aço cromado / retificado
ZINC = 0xC2C7CC         # zincado
BLACK_OXIDE = 0x3A3C41  # aço oxidado preto (parafusos 12.9)
HOLE = 0x15161A         # furo / sombra
BRASS = 0xC9A44C
COPPER = 0xB87333
NYLON = 0xEDEBE2
DELRIN = 0x1E1F22
RUBBER = 0x1C1C1E
RUBBER_RED = 0x9E2A2B
PCB_GREEN = 0x1F6B3A
PCB_BLUE = 0x1D4E8F
PCB_BLACK = 0x23262B
PCB_RED = 0xA52A2A
CHIP = 0x18191C
TERM_GREEN = 0x2F8F5B
TERM_BLUE = 0x2D6CC0
HEADER = 0x202124
WHITE_PLASTIC = 0xEEEEEA
BLACK_PLASTIC = 0x26282C
GREY_PLASTIC = 0x6C7076
YELLOW = 0xF2C200
RED = 0xD02020
ORANGE = 0xE8701A
MDF = 0xB58A5E
GOLD = 0xD4AF37
LED_RED = 0xFF3030
LED_GREEN = 0x30E060
LED_BLUE = 0x3080FF
LABEL = 0xF5F5F0

# ------------------------------------------------------------- utilitários


def r3(v):
    return round(float(v), 3)


def hexc(rgb):
    return '#%06X' % rgb


def tcolor(rgb):
    """RGB -> TColor do Lazarus (BGR em inteiro)."""
    r = (rgb >> 16) & 0xFF
    g = (rgb >> 8) & 0xFF
    b = rgb & 0xFF
    return (b << 16) | (g << 8) | r


def to_xyz(axis, u, v, w):
    if axis == 'z':
        return (u, v, w)
    if axis == 'x':
        return (w, u, v)
    return (v, w, u)  # axis y


def circle(r, n=24, phase=0.0, cx=0.0, cy=0.0):
    return [(cx + r * math.cos(math.radians(phase) + 2 * math.pi * i / n),
             cy + r * math.sin(math.radians(phase) + 2 * math.pi * i / n)) for i in range(n)]


def hexagon(across_flats, phase=0.0, cx=0.0, cy=0.0):
    return circle(across_flats / math.sqrt(3), 6, phase, cx, cy)


def rounded_rect(w, h, rad, n=6, x0=0.0, y0=0.0):
    rad = min(rad, w / 2, h / 2)
    pts = []
    corners = [(x0 + w - rad, y0 + rad, -90), (x0 + w - rad, y0 + h - rad, 0),
               (x0 + rad, y0 + h - rad, 90), (x0 + rad, y0 + rad, 180)]
    for cx, cy, a0 in corners:
        for i in range(n + 1):
            a = math.radians(a0 + 90.0 * i / n)
            pts.append((cx + rad * math.cos(a), cy + rad * math.sin(a)))
    return pts


def convex_hull(points):
    pts = sorted(set((round(x, 4), round(y, 4)) for x, y in points))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def hull_of_circles(circles, n=20):
    pts = []
    for cx, cy, r in circles:
        pts += circle(r, n, 0, cx, cy)
    return convex_hull(pts)


def d_shaft(r, flat_depth, n=24):
    """Eixo com chato (D) voltado para +u."""
    lim = r - flat_depth
    pts = []
    for x, y in circle(r, n):
        p = (min(x, lim), y)
        if not pts or abs(pts[-1][0] - p[0]) > 1e-6 or abs(pts[-1][1] - p[1]) > 1e-6:
            pts.append(p)
    return pts


def gear(teeth, r_tip, r_root, tip_frac=0.35):
    """Contorno de polia dentada (dentes trapezoidais)."""
    pts = []
    step = 2 * math.pi / teeth
    for i in range(teeth):
        a = i * step
        half = step / 2
        pts.append((r_root * math.cos(a), r_root * math.sin(a)))
        pts.append((r_tip * math.cos(a + half * (1 - tip_frac)), r_tip * math.sin(a + half * (1 - tip_frac))))
        pts.append((r_tip * math.cos(a + half * (1 + tip_frac)), r_tip * math.sin(a + half * (1 + tip_frac))))
        pts.append((r_root * math.cos(a + step - 0.0001), r_root * math.sin(a + step - 0.0001)))
    return pts


def edge_profile(w, h, features, chamfer=0.5):
    """Contorno retangular W x H percorrido no sentido anti-horário com
    ranhuras/rasgos.  ``features`` = {'bottom'|'right'|'top'|'left':
    [(centro, [(a, d), ...]), ...]} onde ``a`` é o deslocamento ao longo da
    aresta e ``d`` a profundidade para dentro."""
    edges = [
        ('bottom', (0.0, 0.0), (1, 0), (0, 1), w),
        ('right', (w, 0.0), (0, 1), (-1, 0), h),
        ('top', (w, h), (-1, 0), (0, -1), w),
        ('left', (0.0, h), (0, -1), (1, 0), h),
    ]
    pts = []
    for name, o, t, n, length in edges:
        pts.append((o[0] + t[0] * chamfer, o[1] + t[1] * chamfer))
        for center, seq in sorted(features.get(name, []), key=lambda f: f[0]):
            for a, d in seq:
                s = center + a
                pts.append((o[0] + t[0] * s + n[0] * d, o[1] + t[1] * s + n[1] * d))
        pts.append((o[0] + t[0] * (length - chamfer), o[1] + t[1] * (length - chamfer)))
    return pts


# Ranhura V-Slot (série 20, abertura 6,2 mm) em coordenadas (a, d)
VSLOT = [(-4.6, 0), (-3.1, 1.5), (-3.1, 1.9), (-5.6, 4.4), (-5.6, 5.0), (-3.0, 6.2),
         (3.0, 6.2), (5.6, 5.0), (5.6, 4.4), (3.1, 1.9), (3.1, 1.5), (4.6, 0)]
# Rasgo T de mesa (abertura 6,5 mm, alargamento 12 mm)
TSLOT = [(-3.25, 0), (-3.25, 4), (-6, 4), (-6, 9), (6, 9), (6, 4), (3.25, 4), (3.25, 0)]


# ------------------------------------------------------------- construtor


class Geo:
    def __init__(self):
        self.prims = []

    # primitivas -----------------------------------------------------------
    def box(self, at, size, color, **kw):
        p = {'type': 'box', 'at': [r3(v) for v in at], 'size': [r3(v) for v in size], 'color': hexc(color)}
        p.update(kw)
        self.prims.append(p)
        return self

    def cyl(self, at, axis, r, h, color, ri=None, r2=None, seg=None, rot=None, arc=None, caps=None):
        p = {'type': 'cyl', 'axis': axis, 'at': [r3(v) for v in at], 'r': r3(r), 'h': r3(h), 'color': hexc(color)}
        if ri:
            p['ri'] = r3(ri)
        if r2 is not None:
            p['r2'] = r3(r2)
        if seg:
            p['seg'] = int(seg)
        if rot:
            p['rot'] = r3(rot)
        if arc:
            p['arc'] = [r3(arc[0]), r3(arc[1])]
        if caps is False:
            p['caps'] = False
        self.prims.append(p)
        return self

    def prism(self, at, axis, h, poly, color):
        p = {'type': 'prism', 'axis': axis, 'at': [r3(v) for v in at], 'h': r3(h),
             'poly': [[r3(u), r3(v)] for u, v in poly], 'color': hexc(color)}
        self.prims.append(p)
        return self

    def disk(self, at, axis, r, color, seg=None, rot=None):
        p = {'type': 'disk', 'axis': axis, 'at': [r3(v) for v in at], 'r': r3(r), 'color': hexc(color)}
        if seg:
            p['seg'] = int(seg)
        if rot:
            p['rot'] = r3(rot)
        self.prims.append(p)
        return self

    # atalhos --------------------------------------------------------------
    def hole(self, at, axis, d, color=HOLE):
        return self.disk(at, axis, d / 2.0, color, seg=16)

    def thread(self, at, axis, d_major, length, pitch, color=STEEL, core=None, max_bands=36):
        """Haste roscada: núcleo + faixas de filete (sem tampas)."""
        core_color = core if core is not None else shade(color, 0.78)
        rmin = d_major * 0.42
        self.cyl(at, axis, rmin, length, core_color, seg=16)
        spacing = max(pitch, length / float(max_bands))
        band = spacing * 0.5
        n = int((length - band) / spacing)
        u0, v0, w0 = from_xyz(axis, at)
        for i in range(n):
            w = w0 + spacing * 0.25 + i * spacing
            self.cyl(to_xyz(axis, u0, v0, w), axis, d_major / 2.0, band, color, seg=16, caps=False)
        return self

    # caixa envolvente -----------------------------------------------------
    def points(self, p):
        t = p['type']
        if t == 'disk':
            return []
        if t == 'box':
            x, y, z = p['at']
            sx, sy, sz = p['size']
            return [(x, y, z), (x + sx, y + sy, z + sz)]
        ax = p['axis']
        x0, y0, z0 = p['at']
        if t == 'cyl':
            r = max(p['r'], p.get('r2', p['r']))
            a0, a1 = p.get('arc', [0, 360])
            n = 72
            uv = [(0.0, 0.0)] if 'arc' in p else []
            for i in range(n + 1):
                a = math.radians(a0 + (a1 - a0) * i / n)
                uv.append((r * math.cos(a), r * math.sin(a)))
            ws = (0.0, p['h'])
        else:
            uv = p['poly']
            ws = (0.0, p['h'])
        out = []
        for u, v in uv:
            for w in ws:
                dx, dy, dz = to_xyz(ax, u, v, w)
                out.append((x0 + dx, y0 + dy, z0 + dz))
        return out

    def normalize(self):
        pts = []
        for p in self.prims:
            pts += self.points(p)
        mn = [min(q[i] for q in pts) for i in range(3)]
        mx = [max(q[i] for q in pts) for i in range(3)]
        for p in self.prims:
            p['at'] = [r3(p['at'][i] - mn[i]) for i in range(3)]
        return [r3(mx[i] - mn[i]) for i in range(3)]


def from_xyz(axis, xyz):
    x, y, z = xyz
    if axis == 'z':
        return (x, y, z)
    if axis == 'x':
        return (y, z, x)
    return (z, x, y)


def shade(rgb, f):
    r = min(255, int(((rgb >> 16) & 0xFF) * f))
    g = min(255, int(((rgb >> 8) & 0xFF) * f))
    b = min(255, int((rgb & 0xFF) * f))
    return (r << 16) | (g << 8) | b
