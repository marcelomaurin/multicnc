#!/usr/bin/env python3
"""Stage offline suite documentation, preserving relative image/guide paths."""
import argparse
import html
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET


def stage(repo, app, version):
    destination = app / "documentation"
    destination.mkdir(parents=True, exist_ok=True)
    slicer_version = ET.parse(repo / "multislicer/src/app/multislicer.lpi").find(".//VersionInfo/StringTable").attrib["ProductVersion"]
    for name in ("docs", "imgs", "screenshots", "models"):
        source = repo / name
        if source.is_dir():
            shutil.copytree(source, destination / name, dirs_exist_ok=True,
                            ignore=shutil.ignore_patterns("*.zip") if name == "imgs" else None)
    shutil.copy2(repo / "README.md", destination / "README.md")
    for source in sorted(repo.glob("*/README.md")):
        if source.parent.name in ("docs", "imgs", "screenshots", "setup", "dist", "bin", "models"):
            continue
        target = destination / source.relative_to(repo)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        if (source.parent / "docs").is_dir():
            shutil.copytree(source.parent / "docs", target.parent / "docs", dirs_exist_ok=True)
    source = repo / "src/app/README.md"
    target = destination / "src/app/README.md"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    pdfs = sorted((destination / "docs/Manuals").glob("*.pdf"))
    if not pdfs:
        raise SystemExit("Nenhum manual PDF encontrado para o instalador.")
    cards = []
    for pdf in pdfs:
        title = pdf.stem.removeprefix("Manual_do_Usuario_").replace("_PT-BR", "").replace("_", " ")
        cards.append('<li><a href="Manuals/' + html.escape(pdf.name, quote=True) + '">' +
                     html.escape(title) + '</a><span>Manual ilustrado em português · PDF</span></li>')
    page = '''<!doctype html>
<html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Documentação MultiSuite</title>
<style>
body{font:17px/1.6 Segoe UI,Arial,sans-serif;color:#23364c;background:#f2f5f8;margin:0}
main{max-width:980px;margin:32px auto;padding:32px;background:white;border-radius:16px}
h1,h2,h3{line-height:1.25}h1{margin-top:0}a{color:#075bb1}li{margin:12px 0}
.manuals{list-style:none;padding:0}.manuals li{padding:18px;background:#eef5fc;border-radius:8px}
.manuals a{font-size:20px;font-weight:600}.manuals span{display:block;color:#52657a}
img{display:block;max-width:100%;height:auto;margin:auto}figure{margin:24px 0}figcaption{color:#52657a;text-align:center}
footer{border-top:1px solid #d5dfeb;margin-top:28px;padding-top:16px}code{background:#eef2f6;padding:2px 5px}
@media(max-width:650px){main{margin:0;padding:20px;border-radius:0}}
</style><main>
<h1>Documentação MultiSuite</h1>
<p>Setup ''' + html.escape(version) + ''' · Windows 64 bits. Os manuais e as imagens desta página estão incluídos no computador e podem ser consultados sem conexão à internet.</p>
<h2>Manuais do usuário</h2><ul class="manuals">''' + "\n".join(cards) + '''</ul>
<h2>MultiSlicer @@SLICER_VERSION@@: preparar uma impressão</h2>
<ol>
<li>Selecione no topo a impressora cadastrada no MultiCNC ou use <strong>Ajuste manual</strong>. Confira as dimensões da mesa e o bico.</li>
<li>Abra um modelo STL ou 3MF. Posicione, gire ou ajuste a escala na mesa.</li>
<li>Escolha o material, as temperaturas, a qualidade, os suportes e a aderência.</li>
<li>Clique em <strong>Fatiar</strong>. A barra no rodapé mostra o progresso. <strong>Cancelar</strong> ou Esc interrompe o cálculo e preserva a prévia anterior.</li>
<li>Na etapa <strong>Prévia</strong>, selecione a camada e confira paredes, preenchimento e suportes na vista 3D. Use a opção de mostrar somente a camada para inspecionar o interior.</li>
<li>Exporte o G-code. Se alterar os parâmetros, refaça o fatiamento. A execução e a conexão com a impressora são realizadas no MultiCNC.</li>
</ol>
<figure><img src="../imgs/ms_preview3d.png" alt="Prévia 3D dos percursos do MultiSlicer com suportes"><figcaption>Trajetórias acumuladas com suportes.</figcaption></figure>
<figure><img src="../imgs/ms_preview3d_layer.png" alt="Camada isolada com preenchimento e suportes"><figcaption>Inspeção de uma camada na prévia 3D.</figcaption></figure>
<p><a href="../multislicer/README.md">Guia completo do MultiSlicer (texto)</a> · <a href="Manuals/README.md">Índice dos manuais (texto)</a> · <a href="../README.md">Visão geral da suíte (texto)</a></p>
<h2>Modelos de teste para CNC Router</h2>
<p>Os 12 programas GRBL de exemplo incluem quadrados, círculos, furação, bolsão, gravação e superfície 3D. Estão disponíveis na pasta <code>documentation/models/cnc_router</code> da instalação.</p>
<p><a href="../models/cnc_router/README.md">Instruções de uso (texto)</a> · <a href="../models/cnc_router/previas.png">Catálogo visual dos modelos</a> · <a href="../models/cnc_router/relatorio_validacao.csv">Relatório de validação</a></p>
<h2>Exercícios por programa</h2>
<p>Cada programa da suíte tem arquivos de exercício e um passo a passo na pasta <code>documentation/models</code> da instalação: LaserArt, MakePCB, RouterPCB, LaserPCB, MakeRouter, MultiCAM, MultiCAD, MultiSlicer, MultiAssembly, MultiCNC e MultiPhysics.</p>
<p><a href="../models/README.md">Índice dos exercícios (texto)</a></p>
<footer>A versão de referência de cada manual está indicada em seu nome e em sua capa. O número do setup é independente da versão de cada aplicativo.</footer>
</main></html>'''
    page = page.replace("@@SLICER_VERSION@@", html.escape(slicer_version))
    (destination / "docs/index.html").write_text(page, encoding="utf-8")
    print(f"Documentação offline: {len(pdfs)} manuais PDF, guias e imagens em {destination}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-dir", type=Path, required=True)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()
    stage(Path(__file__).resolve().parents[1], args.app_dir.resolve(), args.version)
