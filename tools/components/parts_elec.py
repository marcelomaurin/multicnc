"""Motores, spindles e eletrônica (dimensões de datasheets típicos)."""

import math
from geom import *  # noqa: F401,F403


# ------------------------------------------------------------------ motores

def stepper(frame, body_len, shaft_d, shaft_len, boss_d, boss_h, hole_spacing, hole_d,
            chamfer, flat_len=15.0, key=False, connector='jst', rear_shaft=0.0):
    """Motor de passo híbrido: eixo em +Z, corpo a partir de Z=0."""
    g = Geo()
    h = frame / 2
    c = chamfer
    oct_ = [(h - c, -h), (h, -h + c), (h, h - c), (h - c, h), (-h + c, h), (-h, h - c), (-h, -h + c), (-h + c, -h)]
    rear = body_len * 0.22
    front = body_len * 0.22
    stack = body_len - rear - front
    g.prism((0, 0, 0), 'z', rear, oct_, ALU_BLACK)
    g.prism((0, 0, rear), 'z', stack, [(x * 0.985, y * 0.985) for x, y in oct_], 0x4A4E56)
    for f in (0.33, 0.66):
        g.prism((0, 0, rear + stack * f), 'z', 0.6, [(x * 0.99, y * 0.99) for x, y in oct_], 0x34373D)
    g.prism((0, 0, rear + stack), 'z', front, oct_, ALU_BLACK)
    top = body_len
    g.cyl((0, 0, top), 'z', boss_d / 2, boss_h, ALU, seg=36)
    g.cyl((0, 0, top + boss_h), 'z', shaft_d * 0.9, 0.6, CHROME, seg=20)  # rolamento visível
    z0 = top + boss_h
    plain = shaft_len - flat_len
    g.cyl((0, 0, z0), 'z', shaft_d / 2, plain, CHROME, seg=20)
    if key:
        g.cyl((0, 0, z0 + plain), 'z', shaft_d / 2, flat_len, CHROME, seg=20)
        kw = shaft_d * 0.36
        g.box((-kw / 2, shaft_d / 2 - kw * 0.5, z0 + plain + 2), (kw, kw, flat_len - 4), STEEL)
    else:
        g.prism((0, 0, z0 + plain), 'z', flat_len, d_shaft(shaft_d / 2, shaft_d * 0.1), CHROME)
    s = hole_spacing / 2
    for sx in (-1, 1):
        for sy in (-1, 1):
            g.disk((sx * s, sy * s, top), 'z', hole_d / 2, HOLE)
    if rear_shaft:
        g.cyl((0, 0, -rear_shaft), 'z', shaft_d / 2, rear_shaft, CHROME, seg=20)
    if connector == 'jst':
        g.box((-7.8, -h - 4.2, 1.2), (15.6, 4.6, 7.4), WHITE_PLASTIC)
        g.box((-6.6, -h - 4.25, 2.4), (13.2, 0.1, 5.0), HOLE)
    else:
        g.cyl((0, -h, rear * 0.5), 'y', 3.2, 6, RUBBER, seg=14, r2=2.6)
        g.cyl((0, -h - 6, rear * 0.5), 'y', 2.4, 30, RUBBER, seg=12)
    return g


def dc_motor_775():
    g = Geo()
    g.cyl((0, 0, 0), 'z', 21, 4, shade(STEEL, 0.75), seg=40)
    g.cyl((0, 0, 4), 'z', 21, 62.7, STEEL, seg=40)
    g.cyl((0, 0, 66.7), 'z', 8.75, 4.4, ALU, seg=28)
    g.cyl((0, 0, 71.1), 'z', 2.5, 17, CHROME, seg=16)
    for x in (-14.5, 14.5):
        g.disk((x, 0, 66.7), 'z', 2.0, HOLE)
    for a in range(0, 360, 45):
        g.disk((15 * math.cos(math.radians(a + 22.5)), 15 * math.sin(math.radians(a + 22.5)), 66.7), 'z', 2.0, HOLE)
    for x, y, ax in ((21, 0, 'x'), (-21, 0, 'x'), (0, 21, 'y'), (0, -21, 'y')):
        g.disk((x, y, 60), ax, 1.8, HOLE)
    for x in (-7, 7):
        g.box((x - 0.5, -2.5, -6), (1.0, 5.0, 6), COPPER)
    g.cyl((0, 0, -2.5), 'z', 6, 2.5, BLACK_PLASTIC, seg=24)
    return g


def gearmotor_jgb37(ratio_len=26.0):
    g = Geo()
    g.cyl((0, 0, 0), 'z', 17.5, 34, STEEL, seg=36)
    g.cyl((0, 0, -3), 'z', 7, 3, BLACK_PLASTIC, seg=20)
    g.cyl((0, 0, 34), 'z', 18.5, ratio_len, ZINC, seg=36)
    g.cyl((7, 0, 34 + ratio_len), 'z', 6, 6.5, ZINC, seg=24)
    g.prism((7, 0, 40.5 + ratio_len), 'z', 15, [(x + 7, y) for x, y in d_shaft(3, 0.5)], CHROME)
    for a in range(0, 360, 60):
        g.disk((15.5 * math.cos(math.radians(a)), 15.5 * math.sin(math.radians(a)), 34 + ratio_len), 'z', 1.5, HOLE)
    for x in (-5, 5):
        g.box((x - 0.5, -1.5, -8), (1, 3, 5), COPPER)
    return g


def spindle_dc_52():
    """Spindle 500 W Ø52 com ER11: ferramenta em -Z."""
    g = Geo()
    g.cyl((0, 0, 0), 'z', 8.0, 11.5, CHROME, seg=12)
    g.disk((0, 0, 0), 'z', 3.5, HOLE)
    g.cyl((0, 0, 11.5), 'z', 7.0, 5.5, CHROME, seg=20)
    g.cyl((0, 0, 17), 'z', 22.0, 10, ALU, r2=26.0, seg=40)
    g.cyl((0, 0, 27), 'z', 26.0, 115, ALU, seg=40)
    g.cyl((0, 0, 60), 'z', 26.05, 1.0, shade(ALU, 0.6), seg=40, caps=False)
    g.cyl((0, 0, 110), 'z', 26.05, 1.0, shade(ALU, 0.6), seg=40, caps=False)
    g.cyl((0, 0, 142), 'z', 26.0, 25, BLACK_PLASTIC, seg=40)
    for i in range(8):
        a = math.radians(i * 45)
        g.disk((18 * math.cos(a), 18 * math.sin(a), 167), 'z', 3.0, HOLE)
    g.cyl((0, 0, 167), 'z', 6.5, 8, BLACK_PLASTIC, seg=20)
    g.box((8, -3, 167), (10, 6, 6), RED)
    g.box((-18, -3, 167), (10, 6, 6), BLACK_PLASTIC)
    return g


def spindle_water_65():
    g = Geo()
    g.cyl((0, 0, 0), 'z', 8.0, 11.5, CHROME, seg=12)
    g.disk((0, 0, 0), 'z', 3.5, HOLE)
    g.cyl((0, 0, 11.5), 'z', 7.0, 5.5, CHROME, seg=20)
    g.cyl((0, 0, 17), 'z', 22.0, 13, STEEL, r2=32.5, seg=48)
    g.cyl((0, 0, 30), 'z', 32.5, 145, STEEL, seg=48)
    g.disk((0, -32.5, 100), 'y', 9, LABEL, seg=4, rot=45)
    g.cyl((0, 0, 175), 'z', 32.5, 15, ALU_BLACK, seg=48)
    for z in (45, 160):
        g.cyl((14, 32.5, z), 'y', 4.0, 6, BRASS, seg=6)
        g.cyl((14, 38.5, z), 'y', 2.6, 10, BRASS, r2=2.2, seg=14)
    g.cyl((0, 0, 190), 'z', 9.5, 3, CHROME, seg=6)
    g.cyl((0, 0, 193), 'z', 8.0, 12, CHROME, seg=24)
    return g


def laser_module():
    g = Geo()
    g.cyl((20, 20, 0), 'z', 4.5, 8, ALU_BLACK, seg=20)
    g.cyl((20, 20, 8), 'z', 7, 10, ALU_BLACK, seg=24)
    g.box((0, 0, 18), (40, 40, 52), ALU_BLACK)
    for i in range(8):
        g.box((0.6 + i * 5, -0.05, 22), (2.2, 0.1, 44), 0x111214)
    g.box((0, 0, 70), (40, 40, 10), BLACK_PLASTIC)
    g.disk((20, 20, 80), 'z', 18, HOLE, seg=24)
    g.cyl((20, 20, 80), 'z', 5, 0.5, BLACK_PLASTIC, seg=16)
    g.box((40, 12, 50), (5, 16, 8), WHITE_PLASTIC)
    g.disk((20, 20, 0), 'z', 3, 0x3070FF, seg=12)
    return g


# --------------------------------------------------------------- eletrônica

def pcb(g, w, d, color, z0=0.0, t=1.6, x0=0.0, y0=0.0, holes=None):
    g.box((x0, y0, z0), (w, d, t), color)
    for hx, hy in holes or []:
        g.disk((x0 + hx, y0 + hy, z0 + t), 'z', 1.6, GOLD, seg=12)
        g.disk((x0 + hx, y0 + hy, z0 + t + 0.001), 'z', 1.0, HOLE, seg=12)
    return z0 + t


def terminal_block(g, x, y, z, n, pitch=5.08, color=TERM_GREEN, along='x', h=10.0, depth=7.6):
    L = n * pitch
    if along == 'x':
        g.box((x, y, z), (L, depth, h), color)
        for i in range(n):
            g.disk((x + pitch * (i + 0.5), y + depth * 0.62, z + h), 'z', 1.5, CHROME, seg=12)
            g.box((x + pitch * (i + 0.5) - 1.3, y - 0.05, z + 1.2), (2.6, 0.1, 2.8), HOLE)
    else:
        g.box((x, y, z), (depth, L, h), color)
        for i in range(n):
            g.disk((x + depth * 0.62, y + pitch * (i + 0.5), z + h), 'z', 1.5, CHROME, seg=12)
            g.box((x - 0.05, y + pitch * (i + 0.5) - 1.3, z + 1.2), (0.1, 2.6, 2.8), HOLE)
    return g


def header(g, x, y, z, nx, ny=1, pitch=2.54, pin_len=6.0, down=False):
    g.box((x, y, z - (2.5 if down else 0)), (nx * pitch, ny * pitch, 2.5), HEADER)
    if not down:
        for i in range(nx):
            for j in range(ny):
                g.box((x + pitch * (i + 0.5) - 0.32, y + pitch * (j + 0.5) - 0.32, z + 2.5),
                      (0.64, 0.64, pin_len), GOLD)
    else:
        for i in range(nx):
            for j in range(ny):
                g.box((x + pitch * (i + 0.5) - 0.32, y + pitch * (j + 0.5) - 0.32, z - 2.5 - pin_len),
                      (0.64, 0.64, pin_len), GOLD)
    return g


def ecap(g, x, y, z, d, h):
    g.cyl((x, y, z), 'z', d / 2, h, 0x20242C, seg=16)
    g.disk((x, y, z + h), 'z', d / 2 - 0.4, STEEL, seg=16)


def chip(g, x, y, z, w, d, h=1.2, color=CHIP):
    g.box((x, y, z), (w, d, h), color)


def heatsink(g, x, y, z, w, d, h, fins=5, color=ALU, along='x'):
    base = h * 0.3
    g.box((x, y, z), (w, d, base), color)
    for i in range(fins):
        if along == 'x':
            fw = d / (2 * fins - 1)
            g.box((x, y + i * 2 * fw, z + base), (w, fw, h - base), color)
        else:
            fw = w / (2 * fins - 1)
            g.box((x + i * 2 * fw, y, z + base), (fw, d, h - base), color)


def stepstick(g, x, y, z, color, chip_color=CHIP, hs_color=ALU):
    """Módulo StepStick 15,2 x 20,3 mm com dissipador (A4988/DRV8825/TMC)."""
    header(g, x, y, z, 8, 1, down=True, pin_len=6.0)
    header(g, x, y + 12.7, z, 8, 1, down=True, pin_len=6.0)
    top = pcb(g, 20.32, 15.24, color, z0=z)
    chip(g, x + 6, y + 4.6, top, 5, 5, 0.9, chip_color)
    heatsink(g, x + 5.2, y + 3.6, top + 0.9, 9, 9, 5, 4, hs_color)
    g.cyl((x + 3, y + 7.6, top), 'z', 1.4, 1.4, 0x2050C0, seg=12)  # trimpot
    return top


def driver_tb6600():
    g = Geo()
    g.box((0, 0, 0), (96, 56, 1.6), ALU)                 # base/flanges
    for x in (3.5, 92.5):
        g.disk((x, 10, 1.6), 'z', 1.9, HOLE)
        g.disk((x, 46, 1.6), 'z', 1.9, HOLE)
    g.box((8, 0, 1.6), (80, 56, 24), ALU)               # dissipador
    for i in range(11):
        g.box((8, i * 5.3, 25.6), (80, 2.4, 6.4), ALU)
    g.box((8, 0, 1.6), (80, 0.1, 30.4), shade(ALU, 0.92))
    g.box((0, 3, 1.6), (8, 50, 18), BLACK_PLASTIC)
    g.box((88, 3, 1.6), (8, 50, 18), BLACK_PLASTIC)
    for i in range(6):
        g.disk((4, 6.5 + i * 7.5, 19.6), 'z', 1.6, CHROME, seg=12)
        g.disk((92, 6.5 + i * 7.5, 19.6), 'z', 1.6, CHROME, seg=12)
    g.box((30, 20, 32.01), (24, 14, 0.4), RED)          # chaves DIP
    for i in range(6):
        g.box((31.5 + i * 3.6, 24, 32.4), (1.8, 6, 0.8), WHITE_PLASTIC)
    g.disk((70, 28, 32.0), 'z', 8, LABEL, seg=4, rot=45)
    return g


def driver_dm542():
    g = Geo()
    g.box((0, 0, 0), (118, 75.5, 4), ALU_BLACK)
    for x in (4, 114):
        g.disk((x, 15, 4), 'z', 2.25, HOLE)
        g.disk((x, 60, 4), 'z', 2.25, HOLE)
    g.box((10, 0, 4), (98, 75.5, 18), ALU_BLACK)
    for i in range(9):
        g.box((10, 1 + i * 8.4, 22), (98, 3.0, 11), ALU_BLACK)
    g.box((10, 75.5, 4), (98, 0.1, 18), ALU_BLACK)
    terminal_block(g, 18, -8.5, 4, 6, 5.08, TERM_GREEN, 'x', 11, 8.5)
    terminal_block(g, 60, -8.5, 4, 6, 5.08, TERM_GREEN, 'x', 11, 8.5)
    g.disk((60, 37, 33), 'z', 10, LABEL, seg=4, rot=45)
    g.disk((100, 8, 22), 'z', 1.0, LED_GREEN, seg=8)
    g.disk((104, 8, 22), 'z', 1.0, LED_RED, seg=8)
    return g


def stepstick_part(color, chip_color=CHIP, hs_color=ALU):
    g = Geo()
    stepstick(g, 0, 0, 8.5, color, chip_color, hs_color)
    return g


def psu(w, d, h, fan=False, terminals=9):
    g = Geo()
    g.box((0, 0, 0), (w, d, h), STEEL)
    tb = 13.0
    g.box((0, 0, 0), (tb, d, h * 0.65), BLACK_PLASTIC)
    for i in range(terminals):
        y = 6 + i * (d - 12) / max(1, terminals - 1)
        g.disk((tb * 0.55, y, h * 0.65), 'z', 2.0, CHROME, seg=12)
        g.box((0, y - 2.2, h * 0.3), (0.1, 4.4, h * 0.25), HOLE)
    g.box((0, 0, h * 0.65), (tb, d, h * 0.35), STEEL)
    g.disk((tb + 6, d - 10, h), 'z', 1.5, LED_GREEN, seg=10)
    g.disk((tb + 6, d - 18, h), 'z', 2.0, 0x2060D0, seg=10)
    if fan:
        cx, cy = w * 0.62, d / 2
        g.disk((cx, cy, h), 'z', min(d * 0.42, 30), HOLE, seg=32)
        g.cyl((cx, cy, h - 0.6), 'z', 9, 0.4, BLACK_PLASTIC, seg=20)
        g.disk((cx, cy, h + 0.001), 'z', 4, LABEL, seg=16)
    nx, ny = int((w - tb - 20) / 7), int((d - 20) / 7)
    x0 = tb + 14
    for i in range(nx):
        for j in range(ny):
            x, y = x0 + i * 7, 10 + j * 7 + (3.5 if i % 2 else 0)
            if fan and (x - w * 0.62) ** 2 + (y - d / 2) ** 2 < (min(d * 0.42, 30) + 4) ** 2:
                continue
            if y < d - 8:
                g.disk((x, y, h), 'z', 1.8, HOLE, seg=6)
    return g


def board_grblhal():
    g = Geo()
    for x, y in ((4, 4), (96, 4), (4, 66), (96, 66)):
        g.prism((x, y, 0), 'z', 3, hexagon(5.0), BRASS)
    top = pcb(g, 100, 70, PCB_BLACK, z0=3)
    chip(g, 44, 30, top, 10, 10, 1.4)
    chip(g, 30, 30, top, 4, 4, 0.9)
    for i in range(5):
        header(g, 8 + i * 17, 52, top, 4, 1, pin_len=5.8)
    terminal_block(g, 4, 0, top, 10, 3.5, TERM_GREEN, 'x', 8.5, 7.0)
    terminal_block(g, 44, 0, top, 10, 3.5, TERM_GREEN, 'x', 8.5, 7.0)
    terminal_block(g, 84, 22, top, 2, 5.08, TERM_GREEN, 'y', 10, 7.6)
    g.box((90, 40, top), (10, 9, 3.3), CHROME)          # USB-C
    g.box((84, 50, top), (16, 16, 13.5), CHROME)        # RJ45
    for x, y in ((70, 30), (76, 30), (70, 38)):
        ecap(g, x, y, top, 6.3, 7.7)
    for i in range(4):
        g.disk((20 + i * 4, 45, top), 'z', 0.8, (LED_GREEN, LED_RED, LED_BLUE, LED_GREEN)[i], seg=8)
    return g


def board_fluidnc_6x():
    g = Geo()
    for x, y in ((4, 4), (116, 4), (4, 86), (116, 86)):
        g.prism((x, y, 0), 'z', 3, hexagon(5.0), BRASS)
    top = pcb(g, 120, 90, PCB_BLUE, z0=3)
    for i in range(6):
        header(g, 6 + i * 19, 42, top, 8, 1, pin_len=2)
        header(g, 6 + i * 19, 54.7, top, 8, 1, pin_len=2)
        stepstick(g, 6 + i * 19, 42, top + 2.5 + 6.0 - 6.0 + 2.5, 0x6A2C91)
        terminal_block(g, 6 + i * 19, 0, top, 4, 3.5, TERM_GREEN, 'x', 7.5, 6.5)
    g.box((4, 70, top), (25.5, 18, 3.1), CHROME)        # módulo ESP32
    g.box((4, 86, top), (25.5, 2, 0.8), PCB_BLACK)
    terminal_block(g, 100, 70, top, 2, 5.08, TERM_GREEN, 'x', 10, 7.6)
    ecap(g, 90, 74, top, 8, 10)
    g.box((60, 82, top), (8, 8, 3), CHROME)             # USB
    return g


def arduino_uno_cnc_shield():
    g = Geo()
    top = pcb(g, 68.6, 53.3, PCB_BLUE, z0=0, holes=[(14, 2.5), (15.3, 50.7), (66.1, 7.6), (66.1, 35.5)])
    g.box((-6.2, 31.5, top), (16.3, 12.2, 10.9), CHROME)   # USB-B
    g.box((-1.8, 3.3, top), (13.7, 8.9, 10.8), BLACK_PLASTIC)  # P4
    chip(g, 30, 8, top, 35, 7.5, 3.5)                       # ATmega328P DIP
    header(g, 18, 50.5, top, 10, 1, pin_len=0.5)
    header(g, 40, 50.5, top, 8, 1, pin_len=0.5)
    s = top + 10.9
    top2 = pcb(g, 68.6, 53.3, PCB_BLUE, z0=s)
    for i, (x, y) in enumerate(((4, 4), (26, 4), (48, 4), (4, 30))):
        header(g, x, y, top2, 8, 1, pin_len=2)
        header(g, x, y + 12.7, top2, 8, 1, pin_len=2)
        stepstick(g, x, y, top2 + 2.5 + 2.5, PCB_RED)
    terminal_block(g, 54, 34, top2, 2, 5.08, TERM_BLUE, 'y', 10, 7.6)
    header(g, 30, 40, top2, 12, 2, pin_len=6)
    return g


def esp32_devkit():
    g = Geo()
    header(g, 3, 0.5, 0, 15, 1, down=True, pin_len=6)
    header(g, 3, 25.3, 0, 15, 1, down=True, pin_len=6)
    top = pcb(g, 51.5, 28.3, PCB_BLACK, z0=0)
    g.box((0, 5.2, top), (18, 18, 0.8), PCB_BLACK)
    g.box((5, 5.2, top + 0.8), (13, 18, 2.3), CHROME)
    g.box((46.0, 10.4, top), (5.9, 7.5, 2.9), CHROME)        # micro USB
    for y in (3, 22):
        g.box((40, y, top), (3.5, 6, 1.6), CHROME)
        g.cyl((41.75, y + 3, top + 1.6), 'z', 0.9, 0.5, BLACK_PLASTIC, seg=10)
    chip(g, 30, 10, top, 5, 5, 1.0)
    g.disk((36, 14, top), 'z', 0.6, LED_RED, seg=8)
    return g


def relay_module():
    g = Geo()
    top = pcb(g, 50, 26, PCB_BLUE, z0=0, holes=[(3, 3), (47, 3), (3, 23), (47, 23)])
    g.box((14, 5, top), (19, 15.5, 15.3), 0x1F5FB0)
    g.disk((23.5, 12.75, top + 15.3), 'z', 5, LABEL, seg=4, rot=45)
    terminal_block(g, 39, 2.5, top, 3, 5.0, TERM_BLUE, 'y', 10, 7.5)
    header(g, 2, 5.7, top, 1, 3, pin_len=6)
    g.disk((8, 22, top), 'z', 0.7, LED_RED, seg=8)
    return g


def vfd_15kw():
    g = Geo()
    g.box((0, 0, 0), (118, 128, 170), 0xC9CCD0)
    g.box((0, -0.5, 0), (118, 0.5, 40), 0x8F949A)          # tampa de bornes
    g.box((20, -1.5, 100), (78, 1.5, 58), 0x2F3237)       # teclado
    g.box((30, -1.6, 136), (58, 0.1, 15), 0x101214)       # display
    for i in range(4):
        g.box((34 + i * 13, -1.65, 139), (9, 0.05, 9), LED_RED)
    for i in range(5):
        g.disk((30 + i * 12, -1.5, 120), 'y', 3.2, (0x606468, 0x606468, 0x20A040, 0xD03030, 0x606468)[i], seg=16)
    g.cyl((88, -1.5, 112), 'y', 6, 5, BLACK_PLASTIC, seg=20, r2=5.2)
    for i in range(8):
        g.box((14 + i * 12, -0.6, 10), (6, 0.1, 22), HOLE)
    for i in range(10):
        g.box((10 + i * 10, 20, 170), (5, 88, 0.1), HOLE)
    g.box((-8, 20, 0), (8, 88, 3), 0xC9CCD0)
    g.box((118, 20, 0), (8, 88, 3), 0xC9CCD0)
    for x in (-4, 122):
        g.disk((x, 30, 3), 'z', 2.5, HOLE)
        g.disk((x, 98, 3), 'z', 2.5, HOLE)
    return g


def estop_box():
    g = Geo()
    g.box((0, 0, 0), (40, 40, 44), YELLOW)
    g.box((0.5, 0.5, 44), (39, 39, 1.5), YELLOW)
    g.cyl((20, 20, 45.5), 'z', 13, 3, BLACK_PLASTIC, seg=28)
    g.cyl((20, 20, 48.5), 'z', 6.5, 6, CHROME, seg=20)
    g.cyl((20, 20, 54.5), 'z', 20, 6, RED, seg=40)
    g.cyl((20, 20, 60.5), 'z', 20, 8.5, RED, r2=13, seg=40)
    g.cyl((20, -2.5, 20), 'y', 5.5, 2.5, BLACK_PLASTIC, seg=16)
    return g


def microswitch_roller():
    """KW12-3: corpo 20 x 6,4 x 10,2 mm; alavanca com roldana."""
    g = Geo()
    g.box((0, 0, 0), (20, 10.2, 6.4), BLACK_PLASTIC)
    g.disk((5.0, 4.0, 6.4), 'z', 1.15, HOLE)
    g.disk((14.5, 4.0, 6.4), 'z', 1.15, HOLE)
    g.box((8.5, 10.2, 2.7), (2.6, 1.0, 1.0), 0xE03030)   # pino atuador
    g.box((3, 11.0, 2.0), (17, 0.4, 2.4), CHROME)         # alavanca
    g.cyl((19.5, 13.4, 1.2), 'z', 2.4, 4.0, BLACK_PLASTIC, seg=18)
    g.disk((19.5, 13.4, 5.2), 'z', 0.8, CHROME, seg=8)
    for x in (1.8, 9.3, 17.2):
        g.box((x, -3.8, 2.6), (0.8, 3.8, 3.2), BRASS)
    return g


def inductive_sensor_m12():
    """LJ12A3-4-Z/BX: face sensora em Z=0 (para baixo)."""
    g = Geo()
    g.cyl((0, 0, 0), 'z', 5.9, 6, ORANGE, seg=24)
    g.thread((0, 0, 6), 'z', 12, 43, 1.0, color=BRASS, max_bands=24)
    for z in (14, 34):
        g.prism((0, 0, z), 'z', 4, hexagon(17), CHROME)
    g.cyl((0, 0, 49), 'z', 6, 12, ORANGE, seg=24)
    g.disk((0, 6, 57), 'y', 1.3, LED_RED, seg=10)
    g.cyl((0, 0, 61), 'z', 2.6, 20, RUBBER, seg=12)
    return g


def optical_endstop():
    g = Geo()
    top = pcb(g, 33, 10.5, PCB_RED, z0=0, holes=[(3.5, 5.25), (29.5, 5.25)])
    g.box((10, 0, top), (13, 6.2, 3), BLACK_PLASTIC)
    g.box((10, 0, top + 3), (4, 6.2, 8), BLACK_PLASTIC)
    g.box((19, 0, top + 3), (4, 6.2, 8), BLACK_PLASTIC)
    g.box((26, 1.6, top), (2.54, 7.62, 8.5), WHITE_PLASTIC)
    g.disk((7, 7.5, top), 'z', 0.7, LED_RED, seg=8)
    return g


def fan(size, thick, color=BLACK_PLASTIC):
    g = Geo()
    s = size
    t = 1.6
    g.box((0, 0, 0), (s, s, t), color)
    g.box((0, 0, thick - t), (s, s, t), color)
    for x, y in ((0, 0), (s - 4, 0), (0, s - 4), (s - 4, s - 4)):
        g.box((x, y, t), (4, 4, thick - 2 * t), color)
    g.disk((s / 2, s / 2, thick), 'z', s * 0.47, HOLE, seg=32)
    g.disk((s / 2, s / 2, 0), 'z', s * 0.47, HOLE, seg=32)
    g.cyl((s / 2, s / 2, 0.5), 'z', s * 0.17, thick - 1, color, seg=24)
    for i in range(7):
        a = math.radians(i * 360 / 7)
        r0, r1 = s * 0.17, s * 0.45
        p = [(r0 * math.cos(a), r0 * math.sin(a)), (r1 * math.cos(a + 0.25), r1 * math.sin(a + 0.25)),
             (r1 * math.cos(a + 0.65), r1 * math.sin(a + 0.65)), (r0 * math.cos(a + 0.5), r0 * math.sin(a + 0.5))]
        g.prism((s / 2, s / 2, thick * 0.4), 'z', thick * 0.2, p, shade(color, 1.4))
    for x, y in ((2, 2), (s - 2, 2), (2, s - 2), (s - 2, s - 2)):
        g.disk((x + (1.5 if x < s / 2 else -1.5), y + (1.5 if y < s / 2 else -1.5), thick), 'z', 1.6, HOLE)
    g.disk((s / 2, s / 2, thick + 0.001), 'z', s * 0.12, LABEL, seg=16)
    return g


def gx16_socket(pins=4):
    g = Geo()
    g.prism((0, 0, 0), 'z', 2.5, hexagon(19), CHROME)
    g.thread((0, 0, -12), 'z', 16, 12, 1.0, color=CHROME, max_bands=8)
    g.cyl((0, 0, 2.5), 'z', 9.5, 2, CHROME, seg=28)
    g.cyl((0, 0, 4.5), 'z', 8.0, 7, CHROME, seg=28)
    g.disk((0, 0, 11.5), 'z', 6.5, BLACK_PLASTIC, seg=24)
    for i in range(pins):
        a = math.radians(45 + i * 360 / pins)
        g.disk((3.2 * math.cos(a), 3.2 * math.sin(a), 11.51), 'z', 0.75, GOLD, seg=10)
    return g


def iec_switch_fuse():
    g = Geo()
    g.box((0, 0, 0), (49, 28, 1.5), BLACK_PLASTIC)       # flange
    g.box((2.5, 1.5, -24), (44, 25, 24), BLACK_PLASTIC)  # corpo
    g.box((5, 4.5, 1.5), (22, 19, 0.1), HOLE)            # C14
    for x in (9, 16, 23):
        g.box((x - 0.8, 10.5 if x != 16 else 15.5, 1.6), (1.6, 4, 0.1), CHROME)
    g.box((31, 7.5, 1.5), (13, 13, 3), RED)              # chave KCD1
    g.box((32, 8.5, 4.5), (11, 5.5, 1.2), shade(RED, 1.2))
    g.box((5, 23.5, 1.5), (22, 3.5, 2), GREY_PLASTIC)   # gaveta de fusível
    for x in (4, 18, 32, 44):
        g.box((x, 12, -30), (0.8, 4.8, 6), BRASS)
    return g


def cable_gland_pg7():
    g = Geo()
    g.thread((0, 0, -8), 'z', 12.5, 8, 1.27, color=BLACK_PLASTIC, max_bands=6)
    g.prism((0, 0, 0), 'z', 4, hexagon(15), BLACK_PLASTIC)
    g.prism((0, 0, 4), 'z', 7, circle(7.5, 12), BLACK_PLASTIC)
    g.cyl((0, 0, 11), 'z', 6.5, 3, BLACK_PLASTIC, r2=4.5, seg=20)
    g.disk((0, 0, 14), 'z', 2.5, HOLE)
    return g
