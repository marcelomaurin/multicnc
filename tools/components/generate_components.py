#!/usr/bin/env python3
"""Gera a biblioteca de componentes do MultiAssembly (models/components/mec).

Uso:  python tools/components/generate_components.py [--check]

Cada arquivo JSON mantém os campos lidos pelo MultiAssembly (name, model,
category, kind, material, color, size, ports, description) e acrescenta:
  geometry  - primitivas 3D em mm (ver geom.py e models/components/README.md)
  specs     - dados técnicos para BOM/consulta
  standard  - norma de referência, quando houver
  mass_g    - massa aproximada

``size`` é calculado a partir da geometria (caixa envolvente real da peça).
Dimensões seguem as normas citadas ou datasheets típicos dos fabricantes;
confira o datasheet do item comprado antes de usinar furações.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from geom import *          # noqa: E402,F401,F403
from parts_mech import *    # noqa: E402,F401,F403
from parts_elec import *    # noqa: E402,F401,F403

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'models', 'components', 'mec')

CATALOG = []


def P(name, kind='apkMechanical', v=0.0):
    return {'name': name, 'kind': kind, 'voltage': float(v)}


MECH = 'apkMechanical'
PWR = 'apkPower'
GND = 'apkGround'
STEP = 'apkStep'
DIR = 'apkDir'
ENA = 'apkEnable'
PWM = 'apkPWM'
DIN = 'apkDigitalInput'
DOUT = 'apkDigitalOutput'
COMM = 'apkCommunication'
AIN = 'apkAnalogInput'


def add(path, name, model, kind, material, color, geo, ports, description, specs=None, standard=None, mass_g=None):
    CATALOG.append(dict(path=path, name=name, model=model, kind=kind, material=material, color=color,
                        geo=geo, ports=ports, description=description, specs=specs or {},
                        standard=standard, mass_g=mass_g))


def coil_ports():
    return [P('SHAFT', MECH), P('A+', PWR), P('A-', PWR), P('B+', PWR), P('B-', PWR)]


# =========================================================== perfis
for mx, my, L, fname in ((1, 1, 300, 'perfil_2020_vslot_300mm'), (1, 1, 500, 'perfil_2020_vslot_500mm'),
                         (1, 1, 1000, 'perfil_2020_vslot_1000mm'), (1, 2, 400, 'perfil_2040_vslot_400mm'),
                         (1, 2, 600, 'perfil_2040_vslot_600mm'), (1, 3, 500, 'perfil_2060_vslot_500mm'),
                         (1, 4, 500, 'perfil_2080_vslot_500mm'), (2, 2, 500, 'perfil_4040_vslot_500mm')):
    W, H = 20 * mx, 20 * my
    kgm = {(1, 1): 0.49, (1, 2): 0.94, (1, 3): 1.36, (1, 4): 1.79, (2, 2): 1.63}[(mx, my)]
    sides = []
    for side, n in (('TOP', mx), ('BOTTOM', mx), ('LEFT', my), ('RIGHT', my)):
        for i in range(n):
            sides.append(P('SLOT_%s%s' % (side, '' if n == 1 else str(i + 1)), MECH))
    add('perfis/%s.json' % fname, 'Perfil Alumínio %d%d V-Slot %dmm' % (W, H, L),
        'V-Slot %d%d' % (W, H), 'ackMechanicalPart', 'Alumínio 6063-T5 anodizado', ALU,
        vslot_profile(mx, my, L), sides + [P('END_A', MECH), P('END_B', MECH)],
        'Perfil estrutural V-Slot %dx%d mm (rasgo 6, série 20) com %d mm; furo central Ø4,2 para rosca M5.'
        % (W, H, L),
        {'secao_mm': [W, H], 'comprimento_mm': L, 'rasgo_mm': 6.2, 'furo_central_mm': 4.2,
         'massa_kg_m': kgm, 'fixacao': 'porca T M5 / M3 série 20'},
        'OpenBuilds V-Slot', round(kgm * L, 0))

add('perfis/perfil_cbeam_4080_500mm.json', 'Perfil C-Beam 4080 500mm', 'C-Beam 40x80', 'ackMechanicalPart',
    'Alumínio 6063-T5 anodizado', ALU, cbeam_profile(500),
    [P('CAVIDADE_FUSO', MECH), P('SLOT_FACE_A', MECH), P('SLOT_FACE_B', MECH), P('END_A', MECH), P('END_B', MECH)],
    'Perfil C-Beam 40x80 mm com canal central aberto para fuso embutido e rasgos V-Slot externos.',
    {'secao_mm': [40, 80], 'comprimento_mm': 500, 'massa_kg_m': 2.2}, 'OpenBuilds C-Beam', 1100)

# =========================================================== fixadores
for d, L in ((3, 6), (3, 10), (3, 16), (3, 20), (4, 10), (4, 16), (5, 20), (5, 40), (6, 20), (8, 30)):
    fname = 'parafuso_m%dx%d_allen' % (d, L)
    dk, k, s, p = ISO4762[d]
    add('fixadores/%s.json' % fname, 'Parafuso M%dx%d Allen' % (d, L), 'DIN 912 M%dx%d 12.9' % (d, L),
        'ackFastenerScrew', 'Aço classe 12.9 oxidado preto', BLACK_OXIDE, screw_socket(d, L),
        [P('ROSCA', MECH), P('CABECA', MECH)],
        'Parafuso cabeça cilíndrica com sextavado interno M%d x %d mm (cabeça Ø%.1f x %.1f, chave %.1f).'
        % (d, L, dk, k, s),
        {'rosca': 'M%d x %.2g' % (d, p), 'comprimento_mm': L, 'cabeca_d_mm': dk, 'cabeca_h_mm': k,
         'chave_allen_mm': s, 'torque_ref_Nm': {3: 2.0, 4: 4.6, 5: 9.5, 6: 16, 8: 39}[d]},
        'DIN 912 / ISO 4762', round(0.0061 * d * d * (L + k), 1))

for d, L in ((5, 8), (5, 10), (5, 16), (5, 25)):
    fname = 'parafuso_m%dx%d_allen' % (d, L) if L in (16, 25) else 'parafuso_m%dx%d_abaulado' % (d, L)
    dk, k, s = ISO7380[d]
    add('fixadores/%s.json' % fname, 'Parafuso M%dx%d Abaulado' % (d, L), 'ISO 7380 M%dx%d' % (d, L),
        'ackFastenerScrew', 'Aço inox A2', CHROME, screw_button(d, L, CHROME), [P('ROSCA', MECH), P('CABECA', MECH)],
        'Parafuso cabeça abaulada M%d x %d mm para perfis V-Slot, placas gantry e rodas.' % (d, L),
        {'rosca': 'M%d x 0.8' % d, 'comprimento_mm': L, 'cabeca_d_mm': dk, 'cabeca_h_mm': k, 'chave_allen_mm': s},
        'ISO 7380', round(0.0061 * d * d * L, 1))

add('fixadores/parafuso_m5x12_escareado.json', 'Parafuso M5x12 Escareado', 'ISO 10642 M5x12', 'ackFastenerScrew',
    'Aço classe 10.9 oxidado preto', BLACK_OXIDE, screw_countersunk(5, 12), [P('ROSCA', MECH), P('CABECA', MECH)],
    'Parafuso cabeça chata (escareada 90°) M5 x 12 mm para placas rentes.',
    {'rosca': 'M5 x 0.8', 'comprimento_total_mm': 12, 'cabeca_d_mm': 11.2, 'chave_allen_mm': 3}, 'ISO 10642', 2.0)

add('fixadores/parafuso_m8x25_sextavado.json', 'Parafuso M8x25 Sextavado', 'DIN 933 M8x25 8.8', 'ackFastenerScrew',
    'Aço classe 8.8 zincado', ZINC, screw_hex(8, 25), [P('ROSCA', MECH), P('CABECA', MECH)],
    'Parafuso sextavado M8 x 25 mm rosca total (chave 13).',
    {'rosca': 'M8 x 1.25', 'comprimento_mm': 25, 'chave_mm': 13, 'torque_ref_Nm': 25}, 'DIN 933 / ISO 4017', 15)

for d in (3, 4, 5, 8):
    s, h = DIN985[d]
    add('fixadores/porca_m%d_travante.json' % d, 'Porca M%d Travante' % d, 'DIN 985 M%d' % d, 'ackFastenerNut',
        'Aço zincado / inserto de nylon', ZINC, nut_nylon(d), [P('FURO_ROSCA', MECH)],
        'Porca autotravante com inserto de nylon M%d (chave %.1f, altura %.1f).' % (d, s, h),
        {'rosca': 'M%d' % d, 'chave_mm': s, 'altura_mm': h}, 'DIN 985 / ISO 10511', round(0.05 * s * s * h / 10, 1))

for d in (5, 8):
    s, m = DIN934[d]
    add('fixadores/porca_m%d_sextavada.json' % d, 'Porca M%d Sextavada' % d, 'DIN 934 M%d' % d, 'ackFastenerNut',
        'Aço classe 8 zincado', ZINC, nut_hex(d), [P('FURO_ROSCA', MECH)],
        'Porca sextavada comum M%d (chave %.0f, altura %.1f).' % (d, s, m),
        {'rosca': 'M%d' % d, 'chave_mm': s, 'altura_mm': m}, 'DIN 934 / ISO 4032', round(0.05 * s * s * m / 10, 1))

for d in (3, 4, 5, 8):
    d1, d2, h = DIN125[d]
    add('fixadores/arruela_m%d_lisa.json' % d, 'Arruela M%d Lisa' % d, 'DIN 125 M%d' % d, 'ackFastenerWasher',
        'Aço zincado', ZINC, washer(d), [P('FURO', MECH)],
        'Arruela lisa M%d: Ø interno %.1f, Ø externo %.0f, espessura %.1f mm.' % (d, d1, d2, h),
        {'d_int_mm': d1, 'd_ext_mm': d2, 'espessura_mm': h}, 'DIN 125 / ISO 7089', round(0.006 * (d2 ** 2 - d1 ** 2) * h, 2))

add('fixadores/arruela_m5_pressao.json', 'Arruela M5 Pressão', 'DIN 127 B M5', 'ackFastenerWasher',
    'Aço mola oxidado', BLACK_OXIDE, spring_washer(5), [P('FURO', MECH)],
    'Arruela de pressão (mola) M5 contra afrouxamento por vibração.',
    {'d_int_mm': 5.1, 'd_ext_mm': 9.2, 'espessura_mm': 1.2}, 'DIN 127', 0.3)

add('fixadores/porca_t_nut_m5.json', 'Porca T-Nut M5 Martelo', 'Drop-in T-Nut M5 Slot 6', 'ackFastenerNut',
    'Aço carbono zincado', ZINC, tnut_dropin(5), [P('ROSCA', MECH), P('RASGO', MECH)],
    'Porca martelo (gota) M5 inserida pelo rasgo 6 do perfil série 20 após a montagem.',
    {'rosca': 'M5', 'rasgo_mm': 6, 'serie': 20}, None, 2.0)
add('fixadores/porca_t_nut_m3.json', 'Porca T-Nut M3 Martelo', 'Drop-in T-Nut M3 Slot 6', 'ackFastenerNut',
    'Aço carbono zincado', ZINC, tnut_dropin(3), [P('ROSCA', MECH), P('RASGO', MECH)],
    'Porca martelo M3 para rasgo 6 (fixação de placas eletrônicas e suportes leves).',
    {'rosca': 'M3', 'rasgo_mm': 6, 'serie': 20}, None, 2.0)
add('fixadores/porca_t_nut_m5_mola.json', 'Porca T-Nut M5 com Esfera', 'Roll-in T-Nut M5 Slot 6', 'ackFastenerNut',
    'Aço carbono zincado', ZINC, tnut_rollin(5), [P('ROSCA', MECH), P('RASGO', MECH)],
    'Porca T de inserção lateral com esfera de mola: fica posicionada no rasgo antes do aperto.',
    {'rosca': 'M5', 'rasgo_mm': 6, 'serie': 20}, None, 3.0)

add('fixadores/espacador_m3x10.json', 'Espaçador M3x10', 'Espaçador cilíndrico Ø6 M3', 'ackPinSpacer',
    'Latão', BRASS, spacer_round(6, 3.2, 10), [P('FURO', MECH)],
    'Espaçador cilíndrico de latão Ø6 x 10 mm, furo passante 3,2 mm.',
    {'d_ext_mm': 6, 'd_int_mm': 3.2, 'comprimento_mm': 10}, None, 1.8)
add('fixadores/espacador_hex_m3x10_ff.json', 'Espaçador Sextavado M3x10 F-F', 'Standoff M3x10 Fêmea-Fêmea',
    'ackPinSpacer', 'Latão niquelado', BRASS, spacer_hex_ff(3, 5.0, 10), [P('ROSCA_A', MECH), P('ROSCA_B', MECH)],
    'Espaçador sextavado chave 5 com rosca M3 interna nas duas pontas, para placas eletrônicas.',
    {'chave_mm': 5, 'rosca': 'M3', 'comprimento_mm': 10}, None, 1.6)
add('fixadores/rebite_pop_4x10.json', 'Rebite POP 4x10', 'Rebite de repuxo Ø4 x 10', 'ackFastenerRivet',
    'Alumínio / mandril de aço', ALU, rivet_pop(4, 10, 8), [P('FURO', MECH)],
    'Rebite de repuxo Ø4 x 10 mm (aba Ø8) para chapas até ~6 mm.',
    {'d_mm': 4, 'comprimento_mm': 10, 'aba_d_mm': 8, 'furo_mm': 4.1, 'pega_mm': [3.5, 6.0]}, 'ISO 15983', 0.6)
add('fixadores/cantoneira_esquadro_2020.json', 'Cantoneira L 90° 2020', 'Cast Corner Bracket 2020',
    'ackMechanicalPart', 'Alumínio fundido', ALU_DARK, corner_bracket_2020(), [P('FACE_A', MECH), P('FACE_B', MECH)],
    'Cantoneira fundida 90° com nervura para união de perfis série 20 (2 furos Ø5,5).',
    {'abas_mm': [20, 20], 'largura_mm': 20, 'furo_mm': 5.5}, None, 9)

# ================================================== rolamentos e mancais
for code, d, D, B, seal, desc in (('608zz', 8, 22, 7, STEEL, 'dupla blindagem metálica'),
                                  ('625zz', 5, 16, 5, STEEL, 'dupla blindagem (rodas V-Slot)'),
                                  ('623zz', 3, 10, 4, STEEL, 'dupla blindagem (polias tensoras)'),
                                  ('6000zz', 10, 26, 8, STEEL, 'dupla blindagem'),
                                  ('6205', 25, 52, 15, RUBBER_RED, 'vedação de borracha 2RS')):
    name = 'Rolamento %s' % code.upper().replace('ZZ', 'ZZ')
    model = '%s %dx%dx%dmm' % ({'6205': '6205-2RS'}.get(code, code.upper()), d, D, B)
    ports = [P('FURO_%dMM' % d, MECH), P('EXTERNO', MECH)]
    add('rolamentos_mancais/rolamento_%s.json' % code, name, model, 'ackBearing', 'Aço cromo GCr15', CHROME,
        bearing_radial(d, D, B, seal), ports,
        'Rolamento rígido de esferas %d x %d x %d mm com %s.' % (d, D, B, desc),
        {'d_mm': d, 'D_mm': D, 'B_mm': B}, 'ISO 15', round(0.0072 * (D * D - d * d) * B / 10, 1))

add('rolamentos_mancais/rolamento_f623zz.json', 'Rolamento F623ZZ com Flange', 'F623ZZ 3x10x4mm', 'ackBearing',
    'Aço cromo GCr15', CHROME, bearing_flanged(3, 10, 4, 11.5, 1.0), [P('FURO_3MM', MECH), P('EXTERNO', MECH)],
    'Rolamento flangeado 3 x 10 x 4 mm (flange Ø11,5) para polias tensoras de correia GT2.',
    {'d_mm': 3, 'D_mm': 10, 'B_mm': 4, 'flange_mm': 11.5}, None, 1.6)

for code, d, D, L, span in (('lm8uu', 8, 15, 24, 17.5), ('lm8luu', 8, 15, 45, 35.0), ('lm12uu', 12, 21, 30, 23.0)):
    add('rolamentos_mancais/rolamento_linear_%s.json' % code, 'Rolamento Linear %s' % code.upper(),
        '%s %dx%dx%dmm' % (code.upper(), d, D, L), 'ackBearing', 'Aço cromo / gaiola POM', CHROME,
        linear_bearing(d, D, L, span), [P('EIXO_%dMM' % d, MECH), P('EXTERNO', MECH)],
        'Rolamento linear de esferas recirculantes para eixo retificado Ø%d mm (Ø%d x %d mm).' % (d, D, L),
        {'d_mm': d, 'D_mm': D, 'L_mm': L}, None, {8: 14, 12: 31}[d] * (2 if 'l' in code[2:4] else 1))

add('rolamentos_mancais/mancal_kp08.json', 'Mancal Pedestal KP08', 'KP08 Eixo 8mm', 'ackBearing',
    'Liga de zinco / rolamento K08', ALU_DARK, pillow_kp08(), [P('FURO_EIXO', MECH), P('BASE_FIXACAO', MECH)],
    'Mancal pedestal KP08 (furos 42 mm, centro a 15 mm da base) com rolamento autoalinhante.',
    {'d_mm': 8, 'L_mm': 55, 'J_furos_mm': 42, 'H_centro_mm': 15, 'altura_mm': 29, 'furo_fixacao_mm': 5}, None, 50)
add('rolamentos_mancais/mancal_kfl08.json', 'Mancal Flange KFL08', 'KFL08 Eixo 8mm', 'ackBearing',
    'Liga de zinco / rolamento K08', ALU_DARK, flange_kfl(37, 27, 5, 18, 12, 8),
    [P('FURO_EIXO', MECH), P('FLANGE', MECH)],
    'Mancal de flange losangular KFL08: 2 furos a 37 mm, para fuso T8.',
    {'d_mm': 8, 'L_mm': 48, 'J_furos_mm': 37, 'largura_mm': 27, 'altura_total_mm': 12}, None, 30)
add('rolamentos_mancais/bloco_suporte_fk12.json', 'Bloco Mancal BK12 (lado fixo)', 'BK12 para SFU1605',
    'ackBearing', 'Aço C45 oxidado / rolamentos angulares', ALU_BLACK,
    shaft_support_block('BK', 12, 60, 43, 25, 25, 46), [P('FURO_FUSO', MECH), P('BASE_FIXACAO', MECH)],
    'Suporte do lado fixo BK12 com par de rolamentos de contato angular e porca de travamento para fusos SFU1605.',
    {'d_mm': 12, 'W_mm': 60, 'H_mm': 43, 'h_centro_mm': 25, 'L_mm': 25, 'furos_mm': 46}, None, 400)
add('rolamentos_mancais/bloco_suporte_bf12.json', 'Bloco Mancal BF12 (lado livre)', 'BF12 para SFU1605',
    'ackBearing', 'Aço C45 oxidado / rolamento 6001', ALU_BLACK,
    shaft_support_block('BF', 10, 60, 43, 25, 20, 46), [P('FURO_FUSO', MECH), P('BASE_FIXACAO', MECH)],
    'Suporte do lado livre BF12 com rolamento rígido 6001 e anel elástico.',
    {'d_mm': 10, 'W_mm': 60, 'H_mm': 43, 'h_centro_mm': 25, 'L_mm': 20, 'furos_mm': 46}, None, 280)
add('rolamentos_mancais/suporte_eixo_sk8.json', 'Suporte de Eixo SK8', 'SK8 Eixo 8mm', 'ackMechanicalPart',
    'Alumínio', ALU, shaft_support_sk(8, 42, 33, 20, 14), [P('FURO_EIXO', MECH), P('BASE_FIXACAO', MECH)],
    'Suporte de eixo SK8 com aperto por fenda (centro a 20 mm da base).',
    {'d_mm': 8, 'W_mm': 42, 'H_mm': 33, 'h_centro_mm': 20, 'T_mm': 14, 'furos_mm': 32}, None, 24)
add('rolamentos_mancais/suporte_eixo_sk12.json', 'Suporte de Eixo SK12', 'SK12 Eixo 12mm', 'ackMechanicalPart',
    'Alumínio', ALU, shaft_support_sk(12, 42, 37.5, 23, 14), [P('FURO_EIXO', MECH), P('BASE_FIXACAO', MECH)],
    'Suporte de eixo SK12 com aperto por fenda (centro a 23 mm da base).',
    {'d_mm': 12, 'W_mm': 42, 'H_mm': 37.5, 'h_centro_mm': 23, 'T_mm': 14, 'furos_mm': 32}, None, 30)
add('rolamentos_mancais/patim_scs8uu.json', 'Patim Linear SCS8UU', 'SCS8UU Eixo 8mm', 'ackBearing',
    'Alumínio / LM8UU', ALU, linear_unit_scs(8, 34, 30, 22, 11, 15), [P('EIXO_8MM', MECH), P('TOPO', MECH)],
    'Bloco de rolamento linear SCS8UU (LM8UU encapsulado), 4 furos M4 no topo.',
    {'d_mm': 8, 'W_mm': 34, 'L_mm': 30, 'H_mm': 22, 'h_centro_mm': 11}, None, 52)
add('rolamentos_mancais/patim_scs12uu.json', 'Patim Linear SCS12UU', 'SCS12UU Eixo 12mm', 'ackBearing',
    'Alumínio / LM12UU', ALU, linear_unit_scs(12, 42, 36, 28, 14, 21), [P('EIXO_12MM', MECH), P('TOPO', MECH)],
    'Bloco de rolamento linear SCS12UU (LM12UU encapsulado), 4 furos M5 no topo.',
    {'d_mm': 12, 'W_mm': 42, 'L_mm': 36, 'H_mm': 28, 'h_centro_mm': 14}, None, 100)

# ======================================================= guias e fusos
for d, L in ((8, 300), (8, 400), (12, 400)):
    g = Geo().cyl((0, 0, 0), 'z', d / 2, L, CHROME, seg=24)
    add('guias_fusos/eixo_linear_%dmm_%dmm.json' % (d, L), 'Eixo Retificado %dmm %dmm' % (d, L),
        'WCS %dmm h6' % d, 'ackLinearGuide', 'Aço SAE 1045 temperado e cromado', CHROME, g, [P('EIXO', MECH)],
        'Eixo linear retificado Ø%d mm tolerância h6, temperado por indução e cromado duro, %d mm.' % (d, L),
        {'d_mm': d, 'comprimento_mm': L, 'tolerancia': 'h6', 'dureza_HRC': '60±2'}, None,
        round(7.85e-3 * 3.1416 * (d / 2) ** 2 * L, 0))

g, _, _ = rail(12, 8, 300, 25, 12.5, 6)
carriage(g, -7.5, 8, 300 / 2 - 45.4 / 2, 27, 45.4, 3.0, 13.0, 12.6, holes=(20, 20))
add('guias_fusos/guia_linear_mgn12h_300mm.json', 'Guia Linear MGN12H 300mm', 'MGN12 + carro MGN12H',
    'ackLinearGuide', 'Aço rolamento temperado', STEEL, g, [P('TRILHO', MECH), P('CARRO', MECH)],
    'Trilho miniatura MGN12 (furos M3 a cada 25 mm) com 300 mm e um carro longo MGN12H (27 x 45,4 mm, H 13).',
    {'trilho_mm': [12, 8], 'comprimento_mm': 300, 'passo_furos_mm': 25, 'carro': 'MGN12H',
     'carro_mm': [27, 45.4], 'H_mm': 13, 'furos_carro': '4x M3 20x20', 'C_dinamica_kN': 3.7}, 'HIWIN MGN', 300)

g, _, _ = rail(12, 8, 400, 25, 12.5, 6)
carriage(g, -7.5, 8, 400 / 2 - 45.4 / 2, 27, 45.4, 3.0, 13.0, 12.6, holes=(20, 20))
add('guias_fusos/guia_linear_mgn12h_400mm.json', 'Guia Linear MGN12H 400mm', 'MGN12 + carro MGN12H',
    'ackLinearGuide', 'Aço rolamento temperado', STEEL, g, [P('TRILHO', MECH), P('CARRO', MECH)],
    'Trilho miniatura MGN12 com 400 mm e um carro MGN12H.',
    {'trilho_mm': [12, 8], 'comprimento_mm': 400, 'passo_furos_mm': 25, 'carro': 'MGN12H'}, 'HIWIN MGN', 380)

g = Geo()
carriage(g, 0, 8, 0, 27, 45.4, 3.0, 13.0, 12.6, holes=(20, 20))
add('guias_fusos/carro_mgn12h.json', 'Carro MGN12H', 'MGN12H', 'ackLinearGuide', 'Aço rolamento / tampas POM',
    STEEL, g, [P('CARRO', MECH), P('TRILHO', MECH)],
    'Carro longo MGN12H avulso para trilho MGN12 (4 furos M3 em 20 x 20 mm).',
    {'carro_mm': [27, 45.4], 'H_mm': 13, 'furos': '4x M3 20x20'}, 'HIWIN MGN', 45)

g, _, _ = rail(15, 15, 500, 60, 20, 7.5)
add('guias_fusos/guia_linear_hgr15_500mm.json', 'Guia Linear HGR15 500mm', 'HGR15', 'ackLinearGuide',
    'Aço rolamento temperado', STEEL, g, [P('TRILHO', MECH)],
    'Trilho HGR15 (15 x 15 mm, furos M4 a cada 60 mm) com 500 mm; carros HGH15CA/HGW15CC vendidos à parte.',
    {'trilho_mm': [15, 15], 'comprimento_mm': 500, 'passo_furos_mm': 60, 'parafuso': 'M4x16'}, 'HIWIN HG', 700)

g = Geo()
carriage(g, 0, 15, 0, 34, 61.4, 4.3, 28.0, 15.6, holes=(26, 26))
add('guias_fusos/carro_hgh15ca.json', 'Carro HGH15CA', 'HGH15CA', 'ackLinearGuide', 'Aço rolamento / tampas',
    STEEL, g, [P('CARRO', MECH), P('TRILHO', MECH)],
    'Carro HGH15CA (34 x 61,4 mm, H 28 com trilho) para trilho HGR15, 4 furos M4 em 26 x 26 mm.',
    {'carro_mm': [34, 61.4], 'H_mm': 28, 'furos': '4x M4 26x26', 'C_dinamica_kN': 11.4}, 'HIWIN HG', 180)

add('guias_fusos/fuso_trapezoidal_t8_300mm.json', 'Fuso Trapezoidal T8 300mm', 'Tr8x8 (4 entradas)',
    'ackLeadScrew', 'Aço inox 304', CHROME, screw_shaft(8, 300, 2), [P('FUSO', MECH), P('PONTA_MOTOR', MECH)],
    'Fuso trapezoidal Tr8x8 (passo 2, 4 entradas: 8 mm por volta) com 300 mm.',
    {'d_mm': 8, 'passo_mm': 2, 'avanco_mm_volta': 8, 'entradas': 4, 'comprimento_mm': 300}, 'DIN 103', 120)
add('guias_fusos/fuso_trapezoidal_t8_500mm.json', 'Fuso Trapezoidal T8 500mm', 'Tr8x8 (4 entradas)',
    'ackLeadScrew', 'Aço inox 304', CHROME, screw_shaft(8, 500, 2), [P('FUSO', MECH), P('PONTA_MOTOR', MECH)],
    'Fuso trapezoidal Tr8x8 com 500 mm (8 mm por volta).',
    {'d_mm': 8, 'passo_mm': 2, 'avanco_mm_volta': 8, 'entradas': 4, 'comprimento_mm': 500}, 'DIN 103', 200)
add('guias_fusos/fuso_esferas_sfu1204_300mm.json', 'Fuso de Esferas SFU1204 300mm', 'SFU1204-C7 usinado BK10/BF10',
    'ackLeadScrew', 'Aço GCr15 temperado', CHROME, screw_shaft(12, 300, 4, ends=((8, 39), (6, 10))),
    [P('FUSO', MECH), P('PONTA_MOTOR', MECH), P('PONTA_LIVRE', MECH)],
    'Fuso de esferas SFU1204 classe C7, avanço 4 mm, 300 mm total com pontas usinadas para BK10/BF10.',
    {'d_mm': 12, 'avanco_mm_volta': 4, 'classe': 'C7', 'comprimento_mm': 300, 'pontas': 'BK10 / BF10'},
    'ISO 3408', 260)
add('guias_fusos/fuso_esferas_sfu1605_450mm.json', 'Fuso de Esferas SFU1605 450mm', 'SFU1605-C7 usinado BK12/BF12',
    'ackLeadScrew', 'Aço GCr15 temperado', CHROME, screw_shaft(16, 450, 5, ends=((10, 39), (8, 10))),
    [P('FUSO', MECH), P('PONTA_MOTOR', MECH), P('PONTA_LIVRE', MECH)],
    'Fuso de esferas SFU1605 classe C7, avanço 5 mm, 450 mm total com pontas usinadas para BK12/BF12.',
    {'d_mm': 16, 'avanco_mm_volta': 5, 'classe': 'C7', 'comprimento_mm': 450, 'pontas': 'BK12 / BF12'},
    'ISO 3408', 680)
add('guias_fusos/castanha_sfu1605.json', 'Castanha de Esferas SFU1605', 'SFU1605 flange', 'ackFastenerNut',
    'Aço GCr15', STEEL, ballnut_sfu(16, 28, 48, 42, 10, 38), [P('ROSCA_FUSO', MECH), P('FLANGE', MECH)],
    'Castanha de esferas SFU1605 com flange Ø48 (furos em PCD 38) e tubo de recirculação.',
    {'d_mm': 16, 'D_mm': 28, 'flange_mm': 48, 'L_mm': 42, 'pcd_mm': 38, 'furos': '6x Ø5.5'}, None, 300)
add('guias_fusos/castanha_sfu1204.json', 'Castanha de Esferas SFU1204', 'SFU1204 flange', 'ackFastenerNut',
    'Aço GCr15', STEEL, ballnut_sfu(12, 24, 40, 35, 8, 32), [P('ROSCA_FUSO', MECH), P('FLANGE', MECH)],
    'Castanha de esferas SFU1204 com flange Ø40 (furos em PCD 32).',
    {'d_mm': 12, 'D_mm': 24, 'flange_mm': 40, 'L_mm': 35, 'pcd_mm': 32}, None, 170)

# ============================================================== motores
add('motores/motor_passo_nema17_42mm.json', 'Motor de Passo NEMA 17', '17HS4401 1.7A 40mm', 'ackMotor',
    'Aço silício / alumínio', ALU_BLACK,
    stepper(42.3, 40, 5, 24, 22, 2, 31, 3, 4.0), coil_ports(),
    'Motor de passo híbrido 1,8° NEMA 17, 40 mm, 1,7 A/fase, 0,40 N·m; eixo Ø5 com chato, conector JST-PH 6 vias.',
    {'flange_mm': 42.3, 'corpo_mm': 40, 'eixo_mm': [5, 24], 'piloto_mm': [22, 2], 'furos': '4x M3 31 mm',
     'corrente_A': 1.7, 'torque_Nm': 0.40, 'passo_grau': 1.8, 'resistencia_ohm': 1.5, 'indutancia_mH': 2.8},
    'NEMA ICS 16', 280)
add('motores/motor_passo_nema17_48mm.json', 'Motor de Passo NEMA 17 48mm', '17HS8401 1.8A 48mm', 'ackMotor',
    'Aço silício / alumínio', ALU_BLACK,
    stepper(42.3, 48, 5, 24, 22, 2, 31, 3, 4.0), coil_ports(),
    'Motor de passo NEMA 17 de 48 mm, 1,8 A/fase, 0,52 N·m; indicado para eixos de impressoras e CNC 3018.',
    {'flange_mm': 42.3, 'corpo_mm': 48, 'eixo_mm': [5, 24], 'furos': '4x M3 31 mm', 'corrente_A': 1.8,
     'torque_Nm': 0.52, 'passo_grau': 1.8}, 'NEMA ICS 16', 350)
add('motores/motor_passo_nema17_pancake.json', 'Motor de Passo NEMA 17 Pancake', '17HS4023 1.0A 23mm', 'ackMotor',
    'Aço silício / alumínio', ALU_BLACK,
    stepper(42.3, 23, 5, 20, 22, 2, 31, 3, 4.0, flat_len=12), coil_ports(),
    'Motor de passo NEMA 17 curto (23 mm) para extrusoras diretas, 1,0 A/fase, 0,13 N·m.',
    {'flange_mm': 42.3, 'corpo_mm': 23, 'eixo_mm': [5, 20], 'corrente_A': 1.0, 'torque_Nm': 0.13}, 'NEMA ICS 16', 140)
add('motores/motor_passo_nema23_57mm.json', 'Motor de Passo NEMA 23', '23HS8430 3.0A 76mm', 'ackMotor',
    'Aço silício / alumínio', ALU_BLACK,
    stepper(56.4, 76, 8, 21, 38.1, 1.6, 47.14, 5.0, 5.5, flat_len=15, connector='cable'), coil_ports(),
    'Motor de passo NEMA 23 de 76 mm, 3,0 A/fase, 1,9 N·m; eixo Ø8 com chato, saída por cabo.',
    {'flange_mm': 56.4, 'corpo_mm': 76, 'eixo_mm': [8, 21], 'piloto_mm': [38.1, 1.6], 'furos': '4x Ø5 47,14 mm',
     'corrente_A': 3.0, 'torque_Nm': 1.9, 'passo_grau': 1.8}, 'NEMA ICS 16', 1000)
add('motores/motor_passo_nema23_56mm.json', 'Motor de Passo NEMA 23 56mm', '23HS5628 2.8A 56mm', 'ackMotor',
    'Aço silício / alumínio', ALU_BLACK,
    stepper(56.4, 56, 6.35, 21, 38.1, 1.6, 47.14, 5.0, 5.5, flat_len=15, connector='cable'), coil_ports(),
    'Motor de passo NEMA 23 de 56 mm, 2,8 A/fase, 1,26 N·m; eixo Ø6,35.',
    {'flange_mm': 56.4, 'corpo_mm': 56, 'eixo_mm': [6.35, 21], 'corrente_A': 2.8, 'torque_Nm': 1.26},
    'NEMA ICS 16', 700)
add('motores/motor_passo_nema34_86mm.json', 'Motor de Passo NEMA 34', '34HS1456 5.6A 115mm', 'ackMotor',
    'Aço silício / alumínio', ALU_BLACK,
    stepper(86, 115, 14, 32, 73, 1.5, 69.6, 5.5, 8.0, flat_len=25, key=True, connector='cable'), coil_ports(),
    'Motor de passo industrial NEMA 34 de 115 mm, 5,6 A/fase, 8,5 N·m; eixo Ø14 com chaveta.',
    {'flange_mm': 86, 'corpo_mm': 115, 'eixo_mm': [14, 32], 'chaveta_mm': 5, 'piloto_mm': [73, 1.5],
     'furos': '4x Ø5,5 69,6 mm', 'corrente_A': 5.6, 'torque_Nm': 8.5}, 'NEMA ICS 16', 3800)
add('motores/motor_dc_775_24v.json', 'Motor DC 775 24V', 'RS-775 12000 RPM', 'ackMotor', 'Aço / cobre',
    STEEL, dc_motor_775(), [P('SHAFT', MECH), P('VCC', PWR, 24), P('GND', GND)],
    'Motor DC escovado 775 com rolamentos (Ø42 x 66,7 mm), eixo Ø5 x 17 mm, 2 furos M4 a 29 mm.',
    {'d_mm': 42, 'corpo_mm': 66.7, 'eixo_mm': [5, 17], 'furos': '2x M4 29 mm', 'tensao_V': 24,
     'rpm_vazio': 12000, 'corrente_vazio_A': 0.8}, None, 350)
add('motores/motor_dc_redutor_jgb37.json', 'Motor DC com Redutor 12V', 'JGB37-520 12V 100RPM', 'ackMotor',
    'Aço / engrenagens metálicas', STEEL, gearmotor_jgb37(), [P('SHAFT', MECH), P('VCC', PWR, 12), P('GND', GND)],
    'Motorredutor DC JGB37-520 (Ø37), eixo excêntrico Ø6 em D, 100 RPM a 12 V.',
    {'d_mm': 37, 'eixo_mm': [6, 15], 'tensao_V': 12, 'rpm': 100, 'furos': '6x M3'}, None, 170)
add('motores/motor_spindle_500w_52mm.json', 'Spindle DC 500W ER11', 'Spindle 500W 52mm 48V', 'ackSpindle',
    'Alumínio / aço', ALU, spindle_dc_52(), [P('PINCA_ER11', MECH), P('POWER_IN', PWR, 48), P('GND', GND)],
    'Spindle DC 500 W Ø52 refrigerado a ar, pinça ER11 (1–7 mm), 12000 RPM a 48 V; ferramenta em -Z.',
    {'d_mm': 52, 'comprimento_mm': 175, 'pinca': 'ER11', 'potencia_W': 500, 'tensao_V': 48, 'rpm_max': 12000,
     'suporte': 'Ø52'}, None, 1300)
add('motores/spindle_ac_1500w_65mm.json', 'Spindle AC Trifásico 1.5kW', 'GDZ-65-1.5 24000RPM', 'ackSpindle',
    'Aço / alumínio', STEEL, spindle_water_65(), [P('PINCA_ER11', MECH), P('U', PWR, 220), P('V', PWR, 220),
                                                   P('W', PWR, 220), P('PE', GND)],
    'Spindle trifásico 1,5 kW Ø65 refrigerado a água (2 bicos), ER11, 24000 RPM, para inversor VFD 220 V.',
    {'d_mm': 65, 'comprimento_mm': 205, 'pinca': 'ER11', 'potencia_W': 1500, 'tensao_V': 220, 'frequencia_Hz': 400,
     'rpm_max': 24000, 'refrigeracao': 'água', 'conector': 'aviação 4 pinos'}, None, 2800)
add('motores/modulo_laser_10w.json', 'Módulo Laser 10W 450nm', 'Diodo 450nm 10W óptico (TTL/PWM)', 'ackSpindle',
    'Alumínio anodizado', ALU_BLACK, laser_module(), [P('VCC', PWR, 12), P('GND', GND), P('PWM', PWM, 5)],
    'Módulo de laser de diodo 10 W ópticos (450 nm) com dissipador e ventoinha, controle TTL/PWM 5 V.',
    {'potencia_optica_W': 10, 'comprimento_onda_nm': 450, 'tensao_V': 12, 'controle': 'PWM 5 V',
     'aviso': 'use óculos de proteção para 450 nm'}, None, 420)

# ============================================================ transmissão
add('transmissao/acoplador_flexivel_5x8mm.json', 'Acoplador Flexível 5x8mm', 'Coupler D19L25 5x8mm',
    'ackMechanicalPart', 'Alumínio 7075', ALU, coupler_flex(5, 8, 19, 25),
    [P('ENTRADA_5MM', MECH), P('SAIDA_8MM', MECH)],
    'Acoplamento flexível helicoidal Ø19 x 25 mm, furos 5 e 8 mm com 4 parafusos de fixação M4.',
    {'d_mm': 19, 'L_mm': 25, 'furos_mm': [5, 8], 'desalinhamento_angular_grau': 3}, None, 13)
add('transmissao/acoplador_flexivel_8x8mm.json', 'Acoplador Flexível 8x8mm', 'Coupler D19L25 8x8mm',
    'ackMechanicalPart', 'Alumínio 7075', ALU, coupler_flex(8, 8, 19, 25),
    [P('ENTRADA_8MM', MECH), P('SAIDA_8MM', MECH)],
    'Acoplamento flexível helicoidal Ø19 x 25 mm, furos 8 e 8 mm.', {'d_mm': 19, 'L_mm': 25, 'furos_mm': [8, 8]},
    None, 12)
add('transmissao/acoplador_flexivel_635x10mm.json', 'Acoplador Flexível 6,35x10mm', 'Coupler D25L30 6.35x10mm',
    'ackMechanicalPart', 'Alumínio 7075', ALU, coupler_flex(6.35, 10, 25, 30),
    [P('ENTRADA_6_35MM', MECH), P('SAIDA_10MM', MECH)],
    'Acoplamento flexível Ø25 x 30 mm entre NEMA 23 (Ø6,35) e ponta de fuso SFU1605 (Ø10).',
    {'d_mm': 25, 'L_mm': 30, 'furos_mm': [6.35, 10]}, None, 26)
add('transmissao/acoplador_rigido_5x8mm.json', 'Acoplador Rígido 5x8mm', 'Rigid Coupler D14L25 5x8mm',
    'ackMechanicalPart', 'Alumínio', ALU, coupler_flex(5, 8, 14, 25, rigid=True),
    [P('ENTRADA_5MM', MECH), P('SAIDA_8MM', MECH)],
    'Acoplamento rígido Ø14 x 25 mm (exige alinhamento preciso entre motor e fuso).',
    {'d_mm': 14, 'L_mm': 25, 'furos_mm': [5, 8]}, None, 9)
add('transmissao/castanha_fuso_t8.json', 'Castanha Latão Fuso T8', 'Brass Nut Tr8x8 Flange', 'ackFastenerNut',
    'Latão', BRASS, leadnut_t8(), [P('ROSCA_T8', MECH), P('FLANGE', MECH)],
    'Castanha de latão com flange Ø22 (4 furos Ø3,5 em PCD 16) para fuso Tr8x8.',
    {'flange_mm': 22, 'corpo_mm': 10.2, 'L_mm': 15, 'pcd_mm': 16}, None, 15)
add('transmissao/castanha_fuso_t8_antifolga.json', 'Castanha T8 Anti-folga', 'Anti-backlash Nut Tr8x8',
    'ackFastenerNut', 'Latão / mola de aço', BRASS, leadnut_t8(True), [P('ROSCA_T8', MECH), P('FLANGE', MECH)],
    'Castanha dupla com mola de pré-carga para eliminar folga axial em fusos Tr8x8.',
    {'flange_mm': 22, 'L_mm': 33, 'pcd_mm': 16}, None, 28)
add('transmissao/correia_gt2_fechada.json', 'Correia GT2 6mm Fechada 400mm', 'GT2-400-6 (200 dentes)', 'ackBelt',
    'Borracha com fibra de vidro', RUBBER, belt_loop(400), [P('DENTES', MECH)],
    'Correia sincronizada GT2 fechada (passo 2 mm, 200 dentes, 6 mm) mostrada sobre duas polias de 20 dentes.',
    {'passo_mm': 2, 'largura_mm': 6, 'comprimento_mm': 400, 'dentes': 200}, None, 5)
add('transmissao/correia_gt2_aberta_1000mm.json', 'Correia GT2 6mm Aberta 1000mm', 'GT2-6mm (metro)', 'ackBelt',
    'Borracha com fibra de vidro', RUBBER, belt_open(1000), [P('DENTES', MECH), P('PONTA_A', MECH), P('PONTA_B', MECH)],
    'Correia GT2 aberta, passo 2 mm, largura 6 mm, vendida por metro para eixos com polia e tensor.',
    {'passo_mm': 2, 'largura_mm': 6, 'comprimento_mm': 1000}, None, 8)
for teeth, bore in ((20, 5), (20, 8), (16, 5), (60, 8)):
    fname = 'polia_gt2_%dd_eixo%d' % (teeth, bore)
    add('transmissao/%s.json' % fname, 'Polia GT2 %d Dentes Eixo %dmm' % (teeth, bore),
        'GT2-%dT-W6-B%d' % (teeth, bore), 'ackPulley', 'Alumínio', ALU,
        pulley_gt2(teeth, bore, hub_d=None if teeth < 40 else 20, flanged=teeth < 40),
        [P('FURO_%dMM' % bore, MECH), P('DENTES', MECH)],
        'Polia dentada GT2 (passo 2 mm), %d dentes, Ø primitivo %.2f mm, largura 6 mm, furo %d mm, 2 parafusos M3.'
        % (teeth, teeth * 2 / 3.14159, bore),
        {'dentes': teeth, 'd_primitivo_mm': round(teeth * 2 / 3.14159, 2), 'largura_correia_mm': 6, 'furo_mm': bore,
         'mm_por_volta': teeth * 2}, None, {16: 6, 20: 8, 60: 40}[teeth])
add('transmissao/polia_tensora_gt2_20d.json', 'Polia Tensora GT2 20 Dentes 5mm', 'GT2-20T Idler B5', 'ackPulley',
    'Alumínio / 2x 625ZZ', ALU, idler_gt2(20, 5), [P('FURO_5MM', MECH), P('DENTES', MECH)],
    'Polia tensora GT2 de 20 dentes com rolamentos, furo 5 mm.', {'dentes': 20, 'furo_mm': 5}, None, 7)
add('transmissao/polia_tensora_lisa_3mm.json', 'Polia Tensora Lisa 3mm', 'Idler lisa F623 B3', 'ackPulley',
    'Alumínio / 2x F623ZZ', ALU, idler_gt2(20, 3, toothed=False), [P('FURO_3MM', MECH), P('SUPERFICIE', MECH)],
    'Polia tensora lisa (lado dorsal da correia) com rolamentos, furo 3 mm.', {'furo_mm': 3}, None, 5)

# ============================================================ rodas/carros
add('rodas_carros/roda_vslot_delrin.json', 'Roda V-Slot Delrin', 'Solid V Wheel Delrin + 2x 625ZZ', 'ackBearing',
    'POM (Delrin) / rolamentos 625ZZ', DELRIN, vwheel(), [P('FURO_5MM', MECH), P('PISTA_V', MECH)],
    'Roda em V Ø24,39 x 10,23 mm para perfis V-Slot, com 2 rolamentos 625ZZ e espaçador.',
    {'D_mm': 24.39, 'largura_mm': 10.23, 'furo_mm': 5, 'rolamentos': '2x 625ZZ'}, 'OpenBuilds', 12)
add('rodas_carros/roda_vslot_mini.json', 'Roda Mini V-Slot', 'Mini V Wheel + 2x 625ZZ', 'ackBearing',
    'POM / rolamentos 625ZZ', DELRIN, vwheel(mini=True), [P('FURO_5MM', MECH), P('PISTA_V', MECH)],
    'Roda mini em V Ø15,23 x 8,8 mm para carros compactos em perfis V-Slot.',
    {'D_mm': 15.23, 'largura_mm': 8.8, 'furo_mm': 5}, 'OpenBuilds', 6)
add('rodas_carros/espacador_excentrico_6mm.json', 'Espaçador Excêntrico 6mm', 'Eccentric Spacer 6mm',
    'ackPinSpacer', 'Aço inox', STEEL, eccentric_spacer(6), [P('FURO_5MM', MECH), P('RESSALTO', MECH)],
    'Espaçador excêntrico (0,79 mm) para ajustar a pré-carga das rodas contra o perfil.',
    {'altura_mm': 6, 'excentricidade_mm': 0.79, 'chave_mm': 10, 'furo_mm': 5}, 'OpenBuilds', 4)
add('rodas_carros/espacador_aluminio_6mm.json', 'Espaçador Alumínio 6mm', 'Spacer 10x5.1x6mm', 'ackPinSpacer',
    'Alumínio', ALU, spacer_round(10, 5.1, 6, ALU), [P('FURO_5MM', MECH)],
    'Espaçador Ø10 x 6 mm, furo 5,1 mm, para rodas e polias.', {'d_ext_mm': 10, 'd_int_mm': 5.1, 'altura_mm': 6},
    None, 1)

# ============================================================ placas e suportes


def gantry_plate():
    g = Geo()
    g.prism((0, 0, 0), 'z', 3.17, rounded_rect(65, 65, 4), ALU)
    for i in range(3):
        for j in range(3):
            g.disk((12.5 + 20 * i, 12.5 + 20 * j, 3.17), 'z', 2.55, HOLE)
    for x, y in ((6, 6), (59, 6), (6, 59), (59, 59)):
        g.disk((x, y, 3.17), 'z', 3.6, HOLE)
    return g


def zplate():
    g = Geo()
    g.prism((0, 0, 0), 'z', 10, rounded_rect(100, 80, 3), ALU)
    g.box((35, 25, 10), (30, 30, 12), ALU)
    g.disk((50, 40, 22), 'z', 5, HOLE)
    for x in (10, 90):
        for y in (10, 30, 50, 70):
            g.disk((x, y, 10), 'z', 2.2, HOLE)
    for x, y in ((40, 30), (60, 30), (40, 50), (60, 50)):
        g.disk((x, y, 22), 'z', 1.75, HOLE)
    return g


def bracket_nema17():
    g = Geo()
    g.box((0, 0, 0), (50, 46, 3), BLACK_OXIDE)
    g.box((4, 0, 3), (42, 3, 44), BLACK_OXIDE)
    g.prism((0, 3, 3), 'x', 3, [(0, 0), (30, 0), (0, 30)], BLACK_OXIDE)
    g.prism((47, 3, 3), 'x', 3, [(0, 0), (30, 0), (0, 30)], BLACK_OXIDE)
    g.disk((25, 3, 3 + 21.15), 'y', 11.5, HOLE, seg=24)
    g.disk((25, 0, 3 + 21.15), 'y', 11.5, HOLE, seg=24)
    for sx in (-1, 1):
        for sz in (-1, 1):
            g.disk((25 + sx * 15.5, 0, 24.15 + sz * 15.5), 'y', 1.6, HOLE)
            g.disk((25 + sx * 15.5, 3, 24.15 + sz * 15.5), 'y', 1.6, HOLE)
    for x in (12, 38):
        g.box((x - 2.75, 18, 2.99), (5.5, 20, 0.02), HOLE)
    return g


def bracket_nema23():
    g = Geo()
    g.box((0, 0, 0), (70, 60, 8), ALU)
    g.box((0, 0, 8), (70, 10, 62), ALU)
    g.prism((0, 10, 8), 'x', 6, [(0, 0), (40, 0), (0, 40)], ALU)
    g.prism((64, 10, 8), 'x', 6, [(0, 0), (40, 0), (0, 40)], ALU)
    g.disk((35, 10, 39), 'y', 19.5, HOLE, seg=28)
    g.disk((35, 0, 39), 'y', 19.5, HOLE, seg=28)
    for sx in (-1, 1):
        for sz in (-1, 1):
            g.disk((35 + sx * 23.57, 0, 39 + sz * 23.57), 'y', 2.6, HOLE)
    for x in (12, 58):
        for y in (25, 50):
            g.disk((x, y, 8), 'z', 2.75, HOLE)
    return g


def clamp_52():
    g = Geo()
    g.box((0, 0, 0), (90, 12, 60), ALU)
    g.cyl((45, 40, 5), 'z', 34, 50, ALU, ri=26, seg=48)
    g.box((22, 12, 5), (46, 6, 50), ALU)
    g.box((38, 72, 5), (6, 14, 50), ALU)
    g.box((46, 72, 5), (6, 14, 50), ALU)
    g.cyl((30, 80, 30), 'x', 4.2, 30, BLACK_OXIDE, seg=16)
    g.cyl((26, 80, 30), 'x', 5, 4, BLACK_OXIDE, seg=16)
    for x in (10, 80):
        for z in (12, 48):
            g.disk((x, 0, z), 'y', 2.75, HOLE)
    return g


add('placas_suportes/placa_gantry_vslot_20mm.json', 'Placa Gantry V-Slot 65x65mm', 'Universal Gantry Plate 20mm',
    'ackMechanicalPart', 'Alumínio 6061-T6', ALU, gantry_plate(), [P('ROLDANAS', MECH), P('CORREIA', MECH)],
    'Chapa de 3,17 mm para carro com 4 rodas em perfil V-Slot 20 mm (furos Ø7,2 excêntricos e grade M5 20 mm).',
    {'dim_mm': [65, 65, 3.17], 'furos_rodas_mm': 7.2, 'grade_mm': 20}, 'OpenBuilds', 35)
add('placas_suportes/bloco_carro_eixo_z.json', 'Carro Eixo Z CNC 100x80mm', 'Z-Axis Carriage Plate',
    'ackMechanicalPart', 'Alumínio 6061-T6', ALU, zplate(), [P('MONTAGEM_SPINDLE', MECH), P('BLOCO_PATINS', MECH),
                                                          P('CASTANHA', MECH)],
    'Placa usinada do eixo Z (100 x 80 x 10 mm) com bloco da castanha e furação para patins e suporte do spindle.',
    {'dim_mm': [100, 80, 10], 'bloco_castanha_mm': [30, 30, 12]}, None, 260)
add('placas_suportes/suporte_motor_nema17.json', 'Suporte L Motor NEMA 17', 'NEMA 17 Bracket 90°',
    'ackMechanicalPart', 'Aço 3 mm pintado', BLACK_OXIDE, bracket_nema17(),
    [P('FACE_MOTOR', MECH), P('BASE_FIXACAO', MECH)],
    'Suporte em L de aço 3 mm com nervuras, furo Ø23 e furação M3 31 mm para NEMA 17; base com rasgos.',
    {'espessura_mm': 3, 'furo_piloto_mm': 23, 'furos_motor': '4x M3 31 mm'}, None, 85)
add('placas_suportes/suporte_motor_nema23.json', 'Suporte Usinado NEMA 23', 'NEMA 23 Mount 70mm',
    'ackMechanicalPart', 'Alumínio 6061-T6', ALU, bracket_nema23(), [P('FLANGE_MOTOR', MECH), P('BASE_FIXACAO', MECH)],
    'Suporte em L usinado com nervuras para NEMA 23 (furo Ø39, furação 47,14 mm).',
    {'furo_piloto_mm': 39, 'furos_motor': '4x Ø5,2 47,14 mm'}, None, 220)
add('placas_suportes/suporte_spindle_52mm.json', 'Suporte Spindle 52mm Alumínio', 'Clamp Mount 52mm',
    'ackMechanicalPart', 'Alumínio fundido', ALU, clamp_52(), [P('ABRACADEIRA_52MM', MECH), P('FIXACAO_EIXO_Z', MECH)],
    'Abraçadeira Ø52 com aperto por parafuso M8 e flange traseira de 90 mm para a placa do eixo Z.',
    {'d_mm': 52, 'flange_mm': [90, 60], 'aperto': 'M8'}, None, 300)

# ============================================================ mesas e bases


def mdf_board(w, d, t):
    g = Geo()
    g.box((0, 0, 0), (w, d, t), MDF)
    for x in (15, w - 15):
        for y in (15, d / 2, d - 15):
            g.disk((x, y, t), 'z', 5, shade(MDF, 0.55))
            g.disk((x, y, t + 0.001), 'z', 2.75, HOLE)
    return g


def tslot_table(w, d, t, n):
    pitch = d / n
    feats = [(pitch / 2 + i * pitch, TSLOT) for i in range(n)]
    poly = edge_profile(d, t, {'top': feats}, chamfer=1.0)
    g = Geo()
    g.prism((0, 0, 0), 'x', w, poly, ALU)
    return g


def bed_plate(w, d, t):
    g = Geo()
    g.prism((0, 0, 0), 'z', t, rounded_rect(w, d, 5), ALU)
    for x, y in ((6, 6), (w - 6, 6), (6, d - 6), (w - 6, d - 6)):
        g.disk((x, y, t), 'z', 1.6, HOLE)
    return g


add('mesas_bases/bloco_sacrificial_mdf_300x180.json', 'Spoilboard MDF 300x180mm', 'MDF 12mm', 'ackMechanicalPart',
    'MDF', MDF, mdf_board(300, 180, 12), [P('TOPO_MDF', MECH)],
    'Tábua de sacrifício de MDF 12 mm com 6 furos escareados para M5; refaceie após fixar na mesa.',
    {'dim_mm': [300, 180, 12], 'furos': '6x M5 escareado'}, None, 480)
add('mesas_bases/mesa_ranhurada_300x180.json', 'Mesa Ranhurada T-Slot 300x180mm', 'Bed 3018 T-Slot',
    'ackMechanicalPart', 'Alumínio extrudado', ALU, tslot_table(300, 180, 15, 6),
    [P('SUPERFICIE_USINAGEM', MECH), P('RANHURAS_T', MECH)],
    'Mesa de alumínio com 6 canais em T (abertura 6,5 mm, passo 30 mm) para grampos M6 na CNC 3018.',
    {'dim_mm': [300, 180, 15], 'canais': 6, 'abertura_mm': 6.5, 'passo_mm': 30}, None, 1650)
add('mesas_bases/placa_cama_aluminio_220x220.json', 'Mesa de Alumínio 220x220mm', 'Bed Plate 220x220x3mm',
    'ackMechanicalPart', 'Alumínio 5052', ALU, bed_plate(220, 220, 3), [P('BASE_SUPERIOR', MECH)],
    'Chapa de alumínio 220 x 220 x 3 mm com 4 furos M3 de nivelamento (padrão Ender-3).',
    {'dim_mm': [220, 220, 3], 'furos': '4x M3'}, None, 390)

# ============================================================ eletrônica
add('eletronica/driver_tb6600_4a.json', 'Driver de Passo TB6600 4A', 'TB6600 Microstep 9-42V 4A', 'ackDriver',
    'Dissipador de alumínio / plástico', ALU, driver_tb6600(),
    [P('PUL+', STEP), P('PUL-', GND), P('DIR+', DIR), P('DIR-', GND), P('ENA+', ENA), P('ENA-', GND),
     P('A+', PWR), P('A-', PWR), P('B+', PWR), P('B-', PWR), P('VCC', PWR, 24), P('GND', GND)],
    'Driver de motor de passo TB6600: 9–42 V, até 4,0 A, micropasso até 1/32 por chaves DIP, entradas optoacopladas.',
    {'tensao_V': [9, 42], 'corrente_A': 4.0, 'micropasso': '1..32', 'entrada_sinal': '3,3–5 V opto',
     'freq_max_kHz': 200}, None, 200)
add('eletronica/driver_dm542.json', 'Driver de Passo DM542', 'DM542 18-50V 4.2A', 'ackDriver',
    'Alumínio anodizado', ALU_BLACK, driver_dm542(),
    [P('PUL+', STEP), P('PUL-', GND), P('DIR+', DIR), P('DIR-', GND), P('ENA+', ENA), P('ENA-', GND),
     P('A+', PWR), P('A-', PWR), P('B+', PWR), P('B-', PWR), P('VCC', PWR, 36), P('GND', GND)],
    'Driver digital DM542: 18–50 VDC, 1,0–4,2 A, micropasso até 1/128, para NEMA 23.',
    {'tensao_V': [18, 50], 'corrente_A': 4.2, 'micropasso': '1..128', 'entrada_sinal': '5 V opto'}, None, 280)
for name, fname, model, color, desc, specs, hs in (
        ('Driver A4988', 'driver_a4988', 'Pololu A4988 StepStick', PCB_RED,
         'Módulo StepStick A4988: 8–35 V, até 2 A com dissipação, micropasso até 1/16.',
         {'tensao_V': [8, 35], 'corrente_A': 2.0, 'micropasso': '1..16'}, ALU),
        ('Driver DRV8825', 'driver_drv8825', 'DRV8825 StepStick', 0x6A2C91,
         'Módulo StepStick DRV8825: 8,2–45 V, até 2,2 A, micropasso até 1/32.',
         {'tensao_V': [8.2, 45], 'corrente_A': 2.2, 'micropasso': '1..32'}, ALU),
        ('Driver TMC2209', 'driver_tmc2209', 'TMC2209 StepStick UART', PCB_BLACK,
         'Módulo StepStick TMC2209 silencioso (StealthChop), 4,75–29 V, 2 A RMS, UART e StallGuard.',
         {'tensao_V': [4.75, 29], 'corrente_A_rms': 2.0, 'micropasso': '1..256', 'interface': 'UART'}, 0x6A2C91)):
    add('eletronica/%s.json' % fname, name, model, 'ackDriver', 'PCB FR4 / dissipador', color,
        stepstick_part(color, hs_color=hs),
        [P('STEP', STEP), P('DIR', DIR), P('EN', ENA), P('VMOT', PWR, 24), P('GND', GND), P('VDD', PWR, 5),
         P('1A', PWR), P('1B', PWR), P('2A', PWR), P('2B', PWR)],
        desc, dict(specs, formato='StepStick 15,2 x 20,3 mm'), None, 3)

add('eletronica/controladora_grblhal_32bit.json', 'Controladora CNC GrblHAL 32-bit', 'GrblHAL Cortex-M4 5-Axis',
    'ackController', 'PCB FR4 / conectores', PCB_BLACK, board_grblhal(),
    [P('STEP_X', STEP, 5), P('DIR_X', DIR, 5), P('STEP_Y', STEP, 5), P('DIR_Y', DIR, 5), P('STEP_Z', STEP, 5),
     P('DIR_Z', DIR, 5), P('STEP_A', STEP, 5), P('DIR_A', DIR, 5), P('ENABLE', ENA, 5), P('SPINDLE_PWM', PWM, 5),
     P('SPINDLE_EN', DOUT, 5), P('LIMIT_X', DIN, 5), P('LIMIT_Y', DIN, 5), P('LIMIT_Z', DIN, 5),
     P('PROBE', DIN, 5), P('ESTOP', DIN, 5), P('USB', COMM), P('ETHERNET', COMM), P('POWER_24V', PWR, 24),
     P('GND', GND)],
    'Placa controladora CNC 32 bits (Cortex-M4) com grblHAL: 5 eixos com saídas STEP/DIR externas, USB e Ethernet.',
    {'mcu': 'ARM Cortex-M4', 'eixos': 5, 'firmware': 'grblHAL', 'alimentacao_V': 24, 'saidas_sinal_V': 5}, None, 90)
add('eletronica/controladora_fluidnc_esp32.json', 'Controladora FluidNC ESP32 6 Eixos', 'ESP32 FluidNC 6x StepStick',
    'ackController', 'PCB FR4 / conectores', PCB_BLUE, board_fluidnc_6x(),
    [P('STEP_X', STEP, 3.3), P('DIR_X', DIR, 3.3), P('STEP_Y', STEP, 3.3), P('DIR_Y', DIR, 3.3),
     P('STEP_Z', STEP, 3.3), P('DIR_Z', DIR, 3.3), P('SPINDLE_PWM', PWM, 3.3), P('LIMIT_X', DIN, 3.3),
     P('LIMIT_Y', DIN, 3.3), P('LIMIT_Z', DIN, 3.3), P('PROBE', DIN, 3.3), P('ESTOP', DIN, 3.3),
     P('USB', COMM), P('WIFI', COMM), P('POWER_24V', PWR, 24), P('GND', GND)],
    'Placa ESP32 para FluidNC com 6 soquetes StepStick (drivers incluídos no modelo), Wi-Fi e USB.',
    {'mcu': 'ESP32', 'eixos': 6, 'firmware': 'FluidNC', 'alimentacao_V': [12, 24]}, None, 120)
add('eletronica/arduino_cnc_shield_v3.json', 'Arduino Uno + CNC Shield V3', 'Uno R3 + CNC Shield V3 + 4x A4988',
    'ackController', 'PCB FR4', PCB_BLUE, arduino_uno_cnc_shield(),
    [P('STEP_X', STEP, 5), P('DIR_X', DIR, 5), P('STEP_Y', STEP, 5), P('DIR_Y', DIR, 5), P('STEP_Z', STEP, 5),
     P('DIR_Z', DIR, 5), P('SPINDLE_PWM', PWM, 5), P('LIMIT_X', DIN, 5), P('LIMIT_Y', DIN, 5),
     P('LIMIT_Z', DIN, 5), P('PROBE', DIN, 5), P('ESTOP', DIN, 5), P('USB', COMM), P('VMOT', PWR, 24),
     P('GND', GND)],
    'Conjunto clássico GRBL: Arduino Uno R3 com CNC Shield V3 e 4 drivers A4988 (12–36 V nos motores).',
    {'mcu': 'ATmega328P', 'firmware': 'GRBL 1.1', 'eixos': 4, 'vmot_V': [12, 36]}, None, 60)
add('eletronica/esp32_devkit_v1.json', 'ESP32 DevKit V1', 'ESP32-WROOM-32 30 pinos', 'ackController',
    'PCB FR4', PCB_BLACK, esp32_devkit(),
    [P('VIN', PWR, 5), P('3V3', PWR, 3.3), P('GND', GND), P('USB', COMM), P('TX', COMM), P('RX', COMM),
     P('IN_GPIO34', DIN, 3.3), P('OUT_GPIO2', DOUT, 3.3)],
    'Placa de desenvolvimento ESP32 (Wi-Fi/Bluetooth) com 30 pinos, para FluidNC, painéis e automação.',
    {'mcu': 'ESP32 dual-core 240 MHz', 'logica_V': 3.3, 'pinos': 30}, None, 10)
add('eletronica/fonte_chaveada_24v_15a.json', 'Fonte Chaveada 24V 15A 360W', 'S-360-24', 'ackPowerSupply',
    'Gabinete de aço perfurado', STEEL, psu(215, 115, 50, fan=True),
    [P('AC_L', PWR, 220), P('AC_N', PWR, 220), P('GND_EARTH', GND), P('+24V', PWR, 24), P('0V_GND', GND)],
    'Fonte chaveada 24 V 15 A (360 W) com ventoinha, entrada 110/220 VAC selecionável e ajuste ±10%.',
    {'saida_V': 24, 'saida_A': 15, 'potencia_W': 360, 'entrada_VAC': '110/220'}, None, 900)
add('eletronica/fonte_chaveada_48v_10a.json', 'Fonte Chaveada 48V 10A 480W', 'S-480-48', 'ackPowerSupply',
    'Gabinete de aço perfurado', STEEL, psu(215, 115, 50, fan=True),
    [P('AC_L', PWR, 220), P('AC_N', PWR, 220), P('GND_EARTH', GND), P('+48V', PWR, 48), P('0V_GND', GND)],
    'Fonte chaveada 48 V 10 A (480 W) para spindle DC 500 W e drivers DM542.',
    {'saida_V': 48, 'saida_A': 10, 'potencia_W': 480}, None, 1000)
add('eletronica/fonte_chaveada_12v_5a.json', 'Fonte Chaveada 12V 5A 60W', 'S-60-12', 'ackPowerSupply',
    'Gabinete de aço perfurado', STEEL, psu(159, 97, 38, terminals=7),
    [P('AC_L', PWR, 220), P('AC_N', PWR, 220), P('GND_EARTH', GND), P('+12V', PWR, 12), P('0V_GND', GND)],
    'Fonte chaveada 12 V 5 A (60 W) para laser, ventoinhas e iluminação.',
    {'saida_V': 12, 'saida_A': 5, 'potencia_W': 60}, None, 350)
add('eletronica/inversor_vfd_1500w.json', 'Inversor de Frequência 1.5kW', 'VFD 1.5kW 220V monofásico/trifásico',
    'ackVFD', 'Gabinete plástico / dissipador', 0xC9CCD0, vfd_15kw(),
    [P('AC_L', PWR, 220), P('AC_N', PWR, 220), P('PE', GND), P('U', PWR, 220), P('V', PWR, 220), P('W', PWR, 220),
     P('FWD', DIN), P('DCM', GND), P('VI1', AIN, 10), P('RS485_A', COMM), P('RS485_B', COMM)],
    'Inversor de frequência 1,5 kW (entrada 220 V monofásica, saída trifásica até 400 Hz) para spindle de 24000 RPM.',
    {'potencia_W': 1500, 'entrada_V': 220, 'saida_Hz': [0, 400], 'controle': '0–10 V / RS-485 Modbus'}, None, 1600)
add('eletronica/modulo_rele_5v_1canal.json', 'Módulo Relé 5V 1 Canal', 'SRD-05VDC-SL-C 10A', 'ackRelay',
    'PCB FR4 / relé', PCB_BLUE, relay_module(),
    [P('VCC', PWR, 5), P('GND', GND), P('IN', DIN, 5), P('COM', MECH), P('NO', MECH), P('NC', MECH)],
    'Módulo relé 5 V 1 canal (10 A 250 VAC) com LED, para ligar spindle, aspirador ou bomba.',
    {'bobina_V': 5, 'contato': '10 A 250 VAC / 30 VDC'}, None, 18)
add('eletronica/botao_e_stop_emergencia.json', 'Botão Parada de Emergência E-Stop', 'LAY37-11ZS Cogumelo 40mm',
    'ackEStop', 'Caixa ABS / botão PA', YELLOW, estop_box(), [P('NC_1', DIN), P('NC_2', DIN)],
    'Botão de emergência tipo cogumelo Ø40 com trava giratória, contato NF, em caixa amarela.',
    {'contato': '1 NF', 'furo_painel_mm': 22, 'cogumelo_mm': 40}, 'IEC 60947-5-5', 110)
add('eletronica/sensor_fim_de_curso_microswitch.json', 'Fim de Curso Microswitch', 'KW12-3 Alavanca Roldana',
    'ackEndStop', 'Plástico / contatos prata', BLACK_PLASTIC, microswitch_roller(),
    [P('COM', GND), P('NO', DIN), P('NC', DIN)],
    'Chave microswitch KW12-3 com alavanca e roldana (corpo 20 x 10,2 x 6,4 mm, 2 furos M2).',
    {'corpo_mm': [20, 10.2, 6.4], 'furos': '2x M2 9,5 mm', 'contato': '5 A 250 VAC'}, None, 3)
add('eletronica/sensor_indutivo_lj12a3.json', 'Sensor Indutivo M12 NPN', 'LJ12A3-4-Z/BX', 'ackSensor',
    'Latão niquelado / plástico', BRASS, inductive_sensor_m12(),
    [P('VCC', PWR, 24), P('GND', GND), P('OUT', DOUT, 24)],
    'Sensor indutivo de proximidade M12 NPN NA, alcance 4 mm (metal), 6–36 V; ideal para homing e sonda Z.',
    {'rosca': 'M12x1', 'alcance_mm': 4, 'saida': 'NPN NA', 'tensao_V': [6, 36]}, None, 45)
add('eletronica/sensor_fim_de_curso_optico.json', 'Fim de Curso Óptico', 'TCST2103 módulo', 'ackEndStop',
    'PCB FR4 / sensor de fenda', PCB_RED, optical_endstop(), [P('VCC', PWR, 5), P('GND', GND), P('OUT', DOUT, 5)],
    'Fim de curso óptico de fenda (TCST2103) com LED indicador; sem contato mecânico.',
    {'fenda_mm': 3, 'tensao_V': 5}, None, 3)
add('eletronica/ventoinha_40mm_24v.json', 'Ventoinha 40x40x10 24V', '4010 24V Bucha', 'ackOther',
    'Plástico PBT', BLACK_PLASTIC, fan(40, 10), [P('VCC', PWR, 24), P('GND', GND)],
    'Ventoinha axial 40 x 40 x 10 mm 24 V para drivers e hotends.',
    {'dim_mm': [40, 40, 10], 'tensao_V': 24, 'furos_mm': 32}, None, 9)
add('eletronica/ventoinha_80mm_24v.json', 'Ventoinha 80x80x25 24V', '8025 24V Rolamento', 'ackOther',
    'Plástico PBT', BLACK_PLASTIC, fan(80, 25), [P('VCC', PWR, 24), P('GND', GND)],
    'Ventoinha axial 80 x 80 x 25 mm 24 V para ventilação de gabinete elétrico.',
    {'dim_mm': [80, 80, 25], 'tensao_V': 24, 'furos_mm': 71.5}, None, 45)

# ============================================================ cabos e conectores
add('cabos_conectores/conector_gx16_4p.json', 'Conector Aviação GX16 4 Pinos', 'GX16-4 painel', 'ackConnector',
    'Latão niquelado / baquelite', CHROME, gx16_socket(4),
    [P('P1', MECH), P('P2', MECH), P('P3', MECH), P('P4', MECH)],
    'Conector circular GX16 de 4 pinos para painel (furo Ø16), usado em motores e spindle.',
    {'furo_painel_mm': 16, 'pinos': 4, 'corrente_A': 5}, None, 20)
add('cabos_conectores/tomada_iec_c14_chave.json', 'Entrada IEC C14 com Chave e Fusível', 'C14 + KCD1 + 5x20mm',
    'ackConnector', 'Plástico PA66', BLACK_PLASTIC, iec_switch_fuse(),
    [P('AC_L', PWR, 220), P('AC_N', PWR, 220), P('PE', GND)],
    'Módulo de entrada de energia IEC C14 com chave liga/desliga iluminada e porta-fusível 5 x 20 mm.',
    {'recorte_painel_mm': [47, 27.5], 'corrente_A': 10, 'fusivel': '5x20 mm'}, 'IEC 60320', 30)
add('cabos_conectores/prensa_cabo_pg7.json', 'Prensa-Cabo PG7', 'PG7 Nylon IP68', 'ackConnector',
    'Nylon PA66', BLACK_PLASTIC, cable_gland_pg7(), [P('PASSAGEM', MECH)],
    'Prensa-cabo PG7 IP68 para cabos de 3 a 6,5 mm.', {'rosca': 'PG7', 'cabo_mm': [3, 6.5]}, None, 3)
add('cabos_conectores/esteira_porta_cabo_10x15_500mm.json', 'Esteira Porta-Cabos 10x15 500mm', 'Drag Chain 10x15',
    'ackMechanicalPart', 'Nylon PA66', BLACK_PLASTIC, cable_chain(500, 15, 10),
    [P('PONTA_FIXA', MECH), P('PONTA_MOVEL', MECH)],
    'Esteira porta-cabos 10 x 15 mm (interno) com 500 mm, raio de curvatura 18 mm.',
    {'interno_mm': [15, 10], 'comprimento_mm': 500, 'raio_mm': 18}, None, 60)


# ======================================================================
def build():
    os.makedirs(OUT, exist_ok=True)
    seen = set()
    written = []
    for c in CATALOG:
        path = os.path.join(OUT, *c['path'].split('/'))
        if c['path'] in seen:
            raise SystemExit('arquivo duplicado: ' + c['path'])
        seen.add(c['path'])
        size = c['geo'].normalize()
        category = c['path'].split('/')[0]
        obj = {
            'name': c['name'],
            'model': c['model'],
            'category': category,
            'kind': c['kind'],
            'material': c['material'],
            'color': tcolor(c['color']),
            'size': {'x': size[0], 'y': size[1], 'z': size[2]},
            'ports': c['ports'],
            'description': c['description'],
        }
        if c['standard']:
            obj['standard'] = c['standard']
        if c['mass_g'] is not None:
            obj['mass_g'] = c['mass_g']
        if c['specs']:
            obj['specs'] = c['specs']
        os.makedirs(os.path.dirname(path), exist_ok=True)
        head = json.dumps(obj, ensure_ascii=False, indent=2)
        prims = ',\n'.join('    ' + json.dumps(p, ensure_ascii=False, separators=(', ', ': '))
                           for p in c['geo'].prims)
        text = head[:-2] + ',\n  "geometry": [\n' + prims + '\n  ]\n}\n'
        json.loads(text)
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(text)
        written.append((c['path'], obj['name'], size, len(c['geo'].prims)))
    return written


if __name__ == '__main__':
    rows = build()
    for path, name, size, n in rows:
        print('%-58s %-44s %8.1f x %7.1f x %7.1f  %3d prim' % (path, name, size[0], size[1], size[2], n))
    print('%d componentes gerados em %s' % (len(rows), OUT))
