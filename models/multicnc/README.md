# Exercício do MultiCNC

`quadrado.nc` (CC0-1.0) é o programa do capítulo 27 do manual do MultiCNC: um retângulo de
40 × 30 mm percorrido com o fuso ligado a 1000 RPM e Z em 5 mm (no ar, sem cortar), sem precisar
digitá-lo.

1. No MultiCNC, abra `quadrado.nc` (ou pela Central da suíte).
2. Confira a prévia: o retângulo de (10, 10) a (50, 40), os deslocamentos rápidos (G0) e de corte (G1).
3. **Simular** sem máquina ligada; confira o tempo estimado e os limites.
4. Com a máquina conectada: referencie (homing), zere X/Y/Z no canto do material, rode como
   está (Z = 5 mm, no ar); para cortar de verdade, acrescente uma descida `G1 Z-1 F100` antes do
   primeiro `G1 X50`.

Mais programas de teste: [`../cnc_router`](../cnc_router/README.md) (12 programas de router),
[`../cnc_laser`](../cnc_laser/README.md) (laser) e [`../printer3d`](../printer3d/README.md)
(impressora 3D).
