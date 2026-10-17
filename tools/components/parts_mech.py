"""Construtores paramétricos de peças mecânicas (dimensões de normas/datasheets)."""

import math
from geom import *  # noqa: F401,F403

# --------------------------------------------------------------- fixadores

# DIN 912 / ISO 4762: d -> (dk, k, s_sextavado_interno, passo)
ISO4762 = {3: (5.5, 3.0, 2.5, 0.5), 4: (7.0, 4.0, 3.0, 0.7), 5: (8.5, 5.0, 4.0, 0.8),
           6: (10.0, 6.0, 5.0, 1.0), 8: (13.0, 8.0, 6.0, 1.25)}
# ISO 7380 abaulado: d -> (dk, k, s)
ISO7380 = {3: (5.7, 1.65, 2.0), 4: (7.6, 2.2, 2.5), 5: (9.5, 2.75, 3.0), 6: (10.5, 3.3, 4.0)}
# ISO 10642 escareado: d -> (dk, k, s)
ISO10642 = {3: (6.72, 1.86, 2.0), 4: (8.96, 2.48, 2.5), 5: (11.2, 3.1, 3.0), 6: (13.44, 3.72, 4.0)}
# DIN 933 sextavado: d -> (s, k)
DIN933 = {5: (8.0, 3.5), 6: (10.0, 4.0), 8: (13.0, 5.3), 10: (16.0, 6.4)}
# DIN 934 porca: d -> (s, m)   DIN 985 autotravante: d -> (s, h_total)
DIN934 = {3: (5.5, 2.4), 4: (7.0, 3.2), 5: (8.0, 4.0), 6: (10.0, 5.0), 8: (13.0, 6.5)}
DIN985 = {3: (5.5, 4.0), 4: (7.0, 5.0), 5: (8.0, 5.0), 6: (10.0, 6.0), 8: (13.0, 8.0)}
# DIN 125: d -> (d1, d2, h)    DIN 127 pressão: d -> (d1, d2, s)
DIN125 = {3: (3.2, 7.0, 0.5), 4: (4.3, 9.0, 0.8), 5: (5.3, 10.0, 1.0), 6: (6.4, 12.0, 1.6), 8: (8.4, 16.0, 1.6)}
DIN127 = {5: (5.1, 9.2, 1.2), 8: (8.2, 14.8, 2.0)}
PITCH = {3: 0.5, 4: 0.7, 5: 0.8, 6: 1.0, 8: 1.25, 10: 1.5}


def screw_socket(d, length, color=BLACK_OXIDE):
    dk, k, s, p = ISO4762[d]
    g = Geo()
    g.thread((0, 0, 0), 'z', d, length, p, color=shade(color, 1.05))
    g.cyl((0, 0, length), 'z', dk / 2, k - 0.3, color, seg=28)
    g.cyl((0, 0, length + k - 0.3), 'z', dk / 2, 0.3, color, r2=dk / 2 - 0.3, seg=28)
    g.disk((0, 0, length + k), 'z', s / math.sqrt(3), HOLE, seg=6)
    return g


def screw_button(d, length, color=BLACK_OXIDE):
    dk, k, s = ISO7380[d]
    g = Geo()
    g.thread((0, 0, 0), 'z', d, length, PITCH[d], color=shade(color, 1.05))
    g.cyl((0, 0, length), 'z', dk / 2, k * 0.25, color, seg=28)
    g.cyl((0, 0, length + k * 0.25), 'z', dk / 2, k * 0.75, color, r2=dk * 0.3, seg=28)
    g.disk((0, 0, length + k), 'z', s / math.sqrt(3), HOLE, seg=6)
    return g


def screw_countersunk(d, length, color=BLACK_OXIDE):
    """ISO 10642: comprimento nominal inclui a cabeça."""
    dk, k, s = ISO10642[d]
    g = Geo()
    g.thread((0, 0, 0), 'z', d, length - k, PITCH[d], color=shade(color, 1.05))
    g.cyl((0, 0, length - k), 'z', d / 2, k, color, r2=dk / 2, seg=28)
    g.disk((0, 0, length), 'z', s / math.sqrt(3), HOLE, seg=6)
    return g


def screw_hex(d, length, color=ZINC):
    s, k = DIN933[d]
    g = Geo()
    g.thread((0, 0, 0), 'z', d, length, PITCH[d], color=shade(color, 1.0))
    g.prism((0, 0, length), 'z', k, hexagon(s), color)
    g.cyl((0, 0, length + k), 'z', s * 0.45, 0.2, color, r2=s * 0.42, seg=24)
    return g


def nut_hex(d, color=ZINC):
    s, m = DIN934[d]
    g = Geo()
    g.prism((0, 0, 0), 'z', m, hexagon(s), color)
    g.disk((0, 0, m), 'z', d * 0.5, HOLE, seg=16)
    g.disk((0, 0, 0), 'z', d * 0.5, HOLE, seg=16)
    return g


def nut_nylon(d, color=ZINC):
    s, h = DIN985[d]
    m = h * 0.62
    g = Geo()
    g.prism((0, 0, 0), 'z', m, hexagon(s), color)
    g.cyl((0, 0, m), 'z', s * 0.47, h - m, color, r2=s * 0.42, seg=24)
    g.cyl((0, 0, h - 0.01), 'z', s * 0.36, 0.01, NYLON, ri=d * 0.5, seg=24)
    g.disk((0, 0, 0), 'z', d * 0.5, HOLE, seg=16)
    g.disk((0, 0, h), 'z', d * 0.48, HOLE, seg=16)
    return g


def washer(d, color=ZINC):
    d1, d2, h = DIN125[d]
    return Geo().cyl((0, 0, 0), 'z', d2 / 2, h, color, ri=d1 / 2, seg=28)


def spring_washer(d, color=BLACK_OXIDE):
    d1, d2, s = DIN127[d]
    g = Geo()
    g.cyl((0, 0, 0), 'z', d2 / 2, s, color, ri=d1 / 2, seg=28, arc=(8, 352))
    return g


def tnut_dropin(d, slot=6):
    """Porca martelo/gota para rasgo 6 (série 20)."""
    g = Geo()
    sec = [(0, 0), (11.0, 0), (11.0, 1.6), (8.4, 3.6), (8.4, 5.2), (2.6, 5.2), (2.6, 3.6), (0, 1.6)]
    # perfil no plano (u=Y, v=Z) extrudado em X
    g.prism((0, -5.5, 0), 'x', 10.0, [(u, v) for u, v in sec], ZINC)
    g.disk((5.0, 0, 5.2), 'z', d / 2, HOLE)
    g.disk((5.0, 0, 0), 'z', d / 2, HOLE)
    return g


def tnut_rollin(d):
    g = Geo()
    sec = [(0, 0), (10.0, 0), (10.0, 2.0), (7.8, 4.0), (7.8, 5.5), (2.2, 5.5), (2.2, 4.0), (0, 2.0)]
    g.prism((0, -5.0, 0), 'x', 12.0, sec, ZINC)
    g.cyl((6.0, -2.0, 0.0), 'z', 1.6, 0.6, CHROME, seg=10)  # esfera com mola
    g.disk((6.0, 0, 5.5), 'z', d / 2, HOLE)
    return g


def spacer_round(d_out, d_in, length, color=BRASS):
    return Geo().cyl((0, 0, 0), 'z', d_out / 2, length, color, ri=d_in / 2, seg=24)


def spacer_hex_ff(d, af, length, color=BRASS):
    g = Geo()
    g.prism((0, 0, 0), 'z', length, hexagon(af), color)
    g.disk((0, 0, length), 'z', d * 0.45, HOLE)
    g.disk((0, 0, 0), 'z', d * 0.45, HOLE)
    return g


def rivet_pop(d, length, flange=None):
    flange = flange or d * 2.0
    g = Geo()
    g.cyl((0, 0, 0), 'z', d / 2, length, ALU, seg=20)
    g.cyl((0, 0, length), 'z', flange / 2, d * 0.3, ALU, r2=flange / 2 - 0.4, seg=24)
    g.cyl((0, 0, length + d * 0.3), 'z', d * 0.27, d * 4.5, CHROME, seg=12)  # mandril
    return g


def corner_bracket_2020():
    g = Geo()
    g.box((0, 0, 0), (20, 20, 4), ALU_DARK)
    g.box((0, 0, 4), (4, 20, 16), ALU_DARK)
    g.prism((4, 8, 4), 'y', 4, [(0, 0), (0, 14), (14, 0)], ALU_DARK)
    g.disk((13, 10, 4), 'z', 2.75, HOLE)
    g.disk((4, 10, 13), 'x', 2.75, HOLE)
    return g


# ------------------------------------------------------- rolamentos/mancais

def bearing_radial(d, D, B, seal=STEEL):
    g = Geo()
    t_out = (D - d) * 0.14
    t_in = (D - d) * 0.12
    g.cyl((0, 0, 0), 'z', D / 2, B, CHROME, ri=D / 2 - t_out, seg=32)
    g.cyl((0, 0, 0), 'z', d / 2 + t_in, B, CHROME, ri=d / 2, seg=28)
    g.cyl((0, 0, B * 0.04), 'z', D / 2 - t_out, B * 0.92, seal, ri=d / 2 + t_in, seg=32)
    return g


def bearing_flanged(d, D, B, Df, Bf):
    g = bearing_radial(d, D, B)
    g.cyl((0, 0, B - Bf), 'z', Df / 2, Bf, CHROME, ri=D / 2 - (D - d) * 0.14, seg=32)
    return g


def linear_bearing(d, D, L, groove_span=None):
    g = Geo()
    g.cyl((0, 0, 0), 'z', D / 2, L, CHROME, ri=d / 2 + 1.2, seg=28)
    g.cyl((0, 0, 0), 'z', d / 2 + 1.2, L, RUBBER, ri=d / 2, seg=24)
    if groove_span:
        for z in ((L - groove_span) / 2, (L + groove_span) / 2 - 1.1):
            g.cyl((0, 0, z), 'z', D / 2 + 0.02, 1.1, shade(STEEL, 0.6), seg=28, caps=False)
    return g


def pillow_kp08():
    """KP08: L 55, A 13, J 42, H 15 (centro), H1 5, altura total 29."""
    g = Geo()
    g.box((0, 0, 0), (55, 13, 5), ALU_DARK)
    g.box((13.5, 0, 5), (28, 13, 10), ALU_DARK)
    g.cyl((27.5, 0, 15), 'y', 14, 13, ALU_DARK, seg=32)
    g.cyl((27.5, -1.5, 15), 'y', 9.5, 16, CHROME, ri=4, seg=28)
    g.disk((27.5, 6.5, 29), 'z', 1.5, HOLE)
    g.disk((6.5, 6.5, 5), 'z', 2.75, HOLE)
    g.disk((48.5, 6.5, 5), 'z', 2.75, HOLE)
    return g


def flange_kfl(span, width, thick, boss_d, total, bore):
    g = Geo()
    poly = hull_of_circles([(0, -span / 2, 5.5), (0, span / 2, 5.5), (0, 0, width / 2)], 18)
    # eixo do furo ao longo de Y, flange no plano (u=Z, v=X)
    g.prism((span / 2 + 5.5, 0, width / 2), 'y', thick, poly, ALU_DARK)
    g.cyl((span / 2 + 5.5, thick, width / 2), 'y', boss_d / 2, total - thick, ALU_DARK, seg=28)
    g.cyl((span / 2 + 5.5, -0.8, width / 2), 'y', boss_d / 2 - 2.5, total + 1.6, CHROME, ri=bore / 2, seg=24)
    for x in (5.5, span + 5.5):
        g.disk((x, 0, width / 2), 'y', 2.5, HOLE)
        g.disk((x, thick, width / 2), 'y', 2.5, HOLE)
    return g


def shaft_support_block(kind, d, W, H, h, L, P):
    """BK/BF (fuso de esferas). Eixo do fuso ao longo de Y."""
    g = Geo()
    g.box((0, 0, 0), (W, L, H * 0.42), ALU_BLACK)
    g.prism((0, 0, 0), 'y', L, [(0, W * 0.18), (H, W * 0.28), (H, W * 0.72), (0, W * 0.82)], ALU_BLACK)
    g.cyl((W / 2, -0.01, h), 'y', d * 1.1, L + 0.02, shade(ALU_BLACK, 1.6), ri=d / 2, seg=28)
    if kind == 'BK':
        g.cyl((W / 2, -4, h), 'y', d * 1.05, 4, BLACK_OXIDE, ri=d / 2, seg=24)  # porca de travamento
    for x in (W / 2 - P / 2, W / 2 + P / 2):
        g.disk((x, L / 2, H * 0.42), 'z', 2.75, HOLE)
    return g


def shaft_support_sk(d, W, H, h, T):
    """SK8/SK12: suporte de eixo com fixação por fenda. Eixo ao longo de Y."""
    g = Geo()
    g.prism((0, 0, 0), 'y', T, [(0, 0), (H * 0.3, 0), (H, W * 0.3), (H, W * 0.7), (H * 0.3, W), (0, W)], ALU)
    g.disk((W / 2, T, h), 'y', d / 2, HOLE)
    g.disk((W / 2, 0, h), 'y', d / 2, HOLE)
    g.box((W / 2 - 0.5, 0, h + d / 2), (1, T, H - h - d / 2), HOLE)
    g.disk((W * 0.12 + 2, T / 2, H * 0.3), 'z', 2.25, HOLE)
    return g


def linear_unit_scs(d, W, L, H, h, D):
    """SCS8UU/SCS12UU: rolamento linear encapsulado. Eixo ao longo de Y."""
    g = Geo()
    g.box((0, 0, 0), (W, L, H * 0.45), ALU)
    g.box((W * 0.12, 0, H * 0.45), (W * 0.76, L, H * 0.55), ALU)
    g.cyl((W / 2, -0.01, h), 'y', D / 2, L + 0.02, CHROME, ri=d / 2, seg=24)
    for x in (W * 0.2, W * 0.8):
        for y in (L * 0.25, L * 0.75):
            g.disk((x, y, H), 'z', 1.7, HOLE)
    return g


# --------------------------------------------------------- guias e fusos

def vslot_profile_poly(modules_x, modules_y):
    W, H = 20.0 * modules_x, 20.0 * modules_y
    fx = [(10 + 20 * i, VSLOT) for i in range(modules_x)]
    fy = [(10 + 20 * i, VSLOT) for i in range(modules_y)]
    return edge_profile(W, H, {'bottom': fx, 'top': fx, 'left': fy, 'right': fy})


def vslot_profile(modules_x, modules_y, length, color=ALU):
    g = Geo()
    g.prism((0, 0, 0), 'z', length, vslot_profile_poly(modules_x, modules_y), color)
    for i in range(modules_x):
        for j in range(modules_y):
            c = (10 + 20 * i, 10 + 20 * j)
            g.disk((c[0], c[1], 0), 'z', 2.1, HOLE)
            g.disk((c[0], c[1], length), 'z', 2.1, HOLE)
    return g


def cbeam_profile(length, color=ALU):
    """C-Beam 40x80: canal aberto voltado para +X."""
    side_x = [(10 + 20 * i, VSLOT) for i in range(4)]
    notch = [(-20, 0), (-20, 26), (20, 26), (20, 0)]
    poly = edge_profile(40, 80, {
        'bottom': [(10, VSLOT), (30, VSLOT)],
        'top': [(10, VSLOT), (30, VSLOT)],
        'left': side_x,
        'right': [(10, VSLOT), (40, notch), (70, VSLOT)],
    })
    g = Geo()
    g.prism((0, 0, 0), 'z', length, poly, color)
    for y in (10, 70):
        g.disk((10, y, 0), 'z', 2.1, HOLE)
        g.disk((10, y, length), 'z', 2.1, HOLE)
    return g


def rail(width, height, length, pitch, first, cbore, color=STEEL):
    g = Geo()
    gd = height * 0.18
    sec = [(0, 0), (width, 0), (width, height * 0.45), (width - gd, height * 0.58),
           (width, height * 0.72), (width, height), (0, height), (0, height * 0.72),
           (gd, height * 0.58), (0, height * 0.45)]
    # trilho ao longo de Z; altura em Y (convenção da biblioteca)
    g.prism((0, 0, 0), 'z', length, sec, color)
    z = first
    while z < length - 1:
        g.disk((width / 2, height, z), 'y', cbore / 2, HOLE)
        z += pitch
    return g, width, height


def carriage(g, x0, y_rail_top, z0, W, L, y0, top, inner_w, body_color=STEEL, cap_color=RUBBER_RED,
             holes=(20, 20), axis_len_cap=None):
    """Carro de guia linear em U sobre trilho centrado em x0 + W/2.
    ``y0`` = face inferior do carro (H1 acima da base do trilho), ``top`` = H."""
    cx = x0 + W / 2
    sec = [(x0, y0), (cx - inner_w / 2, y0), (cx - inner_w / 2, y_rail_top + 0.5),
           (cx + inner_w / 2, y_rail_top + 0.5), (cx + inner_w / 2, y0), (x0 + W, y0),
           (x0 + W, top), (x0, top)]
    cap = axis_len_cap or max(2.0, L * 0.09)
    body = L - 2 * cap
    g.prism((0, 0, z0), 'z', cap * 0.4, sec, RUBBER)
    g.prism((0, 0, z0 + cap * 0.4), 'z', cap * 0.6, sec, cap_color)
    g.prism((0, 0, z0 + cap), 'z', body, sec, body_color)
    g.prism((0, 0, z0 + cap + body), 'z', cap * 0.6, sec, cap_color)
    g.prism((0, 0, z0 + cap + body + cap * 0.6), 'z', cap * 0.4, sec, RUBBER)
    hx, hz = holes
    zc = z0 + L / 2
    for sx in (-1, 1):
        for sz in (-1, 1):
            g.disk((cx + sx * hx / 2, top, zc + sz * hz / 2), 'y', 1.4, HOLE)
    g.cyl((cx, top - 2.5, z0 - 3), 'z', 1.6, 3, BRASS, seg=8)  # niple de graxa
    return g


def screw_shaft(d, length, pitch, color=CHROME, ends=None):
    """Fuso ao longo de Z. ``ends`` = ((d1, L1), (d2, L2)) para pontas usinadas."""
    g = Geo()
    z = 0.0
    thr_len = length
    if ends:
        (d1, l1), (d2, l2) = ends
        g.cyl((0, 0, 0), 'z', d1 / 2, l1, CHROME, seg=20)
        z = l1
        thr_len = length - l1 - l2
        g.cyl((0, 0, z + thr_len), 'z', d2 / 2, l2, CHROME, seg=20)
    g.thread((0, 0, z), 'z', d, thr_len, pitch, color=color, max_bands=60)
    return g


def ballnut_sfu(d, D, Df, L, F, bolt_pcd, flat=None):
    """Castanha SFU com flange (flange em Z=0..F). Furo ao longo de Z."""
    g = Geo()
    flat = flat or Df * 0.78
    poly = [(x, max(-flat / 2, min(flat / 2, y))) for x, y in circle(Df / 2, 36)]
    g.prism((0, 0, 0), 'z', F, poly, STEEL)
    g.cyl((0, 0, F), 'z', D / 2, L - F, STEEL, seg=32)
    g.cyl((0, 0, L - 4), 'z', D / 2 - 0.5, 4, RUBBER, seg=32)
    g.disk((0, 0, 0), 'z', d / 2, HOLE)
    g.disk((0, 0, L), 'z', d / 2, HOLE)
    g.box((-D * 0.25, D / 2 - 1, F + 2), (D * 0.5, 4, L - F - 8), STEEL)  # tubo de recirculação
    for a in (0, 45, 135, 180, 225, 315):
        x = bolt_pcd / 2 * math.cos(math.radians(a))
        y = bolt_pcd / 2 * math.sin(math.radians(a))
        if abs(y) < flat / 2 - 2:
            g.disk((x, y, F), 'z', 2.25, HOLE)
    return g


def leadnut_t8(anti_backlash=False):
    g = Geo()
    g.cyl((0, 0, 0), 'z', 11, 3.5, BRASS, seg=32)
    g.cyl((0, 0, 3.5), 'z', 5.1, 11.5, BRASS, seg=24)
    for a in (45, 135, 225, 315):
        g.disk((8 * math.cos(math.radians(a)), 8 * math.sin(math.radians(a)), 3.5), 'z', 1.75, HOLE)
    g.disk((0, 0, 0), 'z', 4, HOLE)
    if anti_backlash:
        g.cyl((0, 0, 15), 'z', 4.6, 8, CHROME, ri=4.2, seg=20)  # mola
        g.cyl((0, 0, 23), 'z', 5.1, 10, BRASS, seg=24)
        g.disk((0, 0, 33), 'z', 4, HOLE)
    else:
        g.disk((0, 0, 15), 'z', 4, HOLE)
    return g


# -------------------------------------------------------------- transmissão

def pulley_gt2(teeth, bore, width=6, hub_d=None, hub_l=7, flanged=True):
    pd = teeth * 2.0 / math.pi
    od = pd - 0.508
    g = Geo()
    hub_d = hub_d or min(od + 1.0, max(bore + 7, od - 0.5))
    g.cyl((0, 0, 0), 'z', hub_d / 2, hub_l, ALU, seg=28)
    z = hub_l
    fd = od + 3.6
    if flanged:
        g.cyl((0, 0, z), 'z', fd / 2, 1.0, ALU, seg=32)
        z += 1.0
    g.prism((0, 0, z), 'z', width + 1.0, gear(teeth, od / 2, od / 2 - 0.75), ALU)
    z += width + 1.0
    if flanged:
        g.cyl((0, 0, z), 'z', fd / 2, 1.0, ALU, seg=32)
        z += 1.0
    g.disk((0, 0, z), 'z', bore / 2, HOLE)
    g.disk((0, 0, 0), 'z', bore / 2, HOLE)
    for a in (0, 90):
        g.disk((hub_d / 2 * math.cos(math.radians(a)), hub_d / 2 * math.sin(math.radians(a)), hub_l / 2),
               'x' if a == 0 else 'y', 1.3, HOLE)
    return g


def idler_gt2(teeth, bore, toothed=True):
    pd = teeth * 2.0 / math.pi
    od = pd - 0.508
    g = Geo()
    fd = od + 5.0
    g.cyl((0, 0, 0), 'z', fd / 2, 1.0, ALU, ri=bore / 2, seg=32)
    if toothed:
        g.prism((0, 0, 1), 'z', 6.5, gear(teeth, od / 2, od / 2 - 0.75), ALU)
    else:
        g.cyl((0, 0, 1), 'z', od / 2, 6.5, ALU, seg=32)
    g.cyl((0, 0, 7.5), 'z', fd / 2, 1.0, ALU, ri=bore / 2, seg=32)
    g.disk((0, 0, 8.5), 'z', bore / 2, HOLE)
    g.disk((0, 0, 0), 'z', bore / 2, HOLE)
    return g


def belt_loop(length, width=6.0, r_pitch=6.37, thick=1.38):
    """Correia fechada no plano XZ (largura em Y)."""
    straight = (length - 2 * math.pi * r_pitch) / 2.0
    ri = r_pitch - thick * 0.4
    ro = ri + thick
    g = Geo()
    g.box((0, 0, ro - ro), (straight, width, thick), RUBBER)
    g.box((0, 0, 2 * ro - thick), (straight, width, thick), RUBBER)
    # semicírculos: eixo Y, (u=Z, v=X)
    g.cyl((0, 0, ro), 'y', ro, width, RUBBER, ri=ri, seg=24, arc=(180, 360))
    g.cyl((straight, 0, ro), 'y', ro, width, RUBBER, ri=ri, seg=24, arc=(0, 180))
    return g


def belt_open(length, width=6.0, thick=1.38):
    g = Geo()
    g.box((0, 0, 0), (length, width, 0.75), RUBBER)
    n = int(length / 2.0)
    step = max(2.0, length / 120.0)
    x = 0.5
    while x < length - 1:
        g.box((x, 0, 0.75), (min(1.0, step * 0.5), width, thick - 0.75), shade(RUBBER, 1.3))
        x += step
    return g


def coupler_flex(d1, d2, D, L, rigid=False):
    g = Geo()
    if rigid:
        g.cyl((0, 0, 0), 'z', D / 2, L, ALU, seg=32)
        g.box((-0.4, 0, 0), (0.8, D / 2 + 0.05, L), HOLE)
    else:
        g.cyl((0, 0, 0), 'z', D / 2, L * 0.3, ALU, seg=32)
        g.cyl((0, 0, L * 0.7), 'z', D / 2, L * 0.3, ALU, seg=32)
        n = 5
        h = L * 0.4 / (2 * n - 1)
        for i in range(2 * n - 1):
            col = ALU if i % 2 == 0 else shade(ALU, 0.35)
            r = D / 2 if i % 2 == 0 else D / 2 - 0.6
            g.cyl((0, 0, L * 0.3 + i * h), 'z', r, h, col, seg=32, rot=i * 18)
    g.disk((0, 0, 0), 'z', d1 / 2, HOLE)
    g.disk((0, 0, L), 'z', d2 / 2, HOLE)
    for z in (L * 0.15, L * 0.85):
        g.disk((D / 2, 0, z), 'x', 1.6, HOLE, seg=6)
        g.disk((0, D / 2, z), 'y', 1.6, HOLE, seg=6)
    return g


def vwheel(solid=False, mini=False):
    """Roda V-Slot (Delrin) com 2 rolamentos 625. Eixo em Z."""
    g = Geo()
    if mini:
        D, B, dv = 15.23, 8.8, 12.21
    else:
        D, B, dv = 24.39, 10.23, 19.5
    color = DELRIN if not solid else 0x2A2E36
    g.cyl((0, 0, 0), 'z', dv / 2, B * 0.22, color, r2=D / 2, seg=32)
    g.cyl((0, 0, B * 0.22), 'z', D / 2, B * 0.56, color, seg=32)
    g.cyl((0, 0, B * 0.78), 'z', D / 2, B * 0.22, color, r2=dv / 2, seg=32)
    g.cyl((0, 0, -0.01), 'z', 8, B + 0.02, CHROME, ri=2.5, seg=24)
    return g


def eccentric_spacer(length=6.0):
    g = Geo()
    g.prism((0, 0, 0), 'z', length, hexagon(10.0), STEEL)
    g.cyl((0.79, 0, length), 'z', 3.6, 2.0, STEEL, seg=20)
    g.disk((0.0, 0, 0), 'z', 2.6, HOLE)
    g.disk((0.79, 0, length + 2), 'z', 2.6, HOLE)
    return g


def cable_chain(length, inner_w, inner_h, link=18.0):
    """Esteira porta-cabos reta ao longo de X."""
    g = Geo()
    wall = 2.0
    W = inner_w + 2 * wall
    H = inner_h + 2 * wall
    n = max(2, int(length / link))
    for i in range(n):
        x = i * link
        col = BLACK_PLASTIC if i % 2 == 0 else shade(BLACK_PLASTIC, 1.25)
        g.box((x, 0, 0), (link - 0.6, wall, H), col)
        g.box((x, W - wall, 0), (link - 0.6, wall, H), col)
        g.box((x + 1.5, wall, H - wall), (link - 3.6, inner_w, wall), col)
        g.box((x + 1.5, wall, 0), (link - 3.6, inner_w, wall), col)
    return g
