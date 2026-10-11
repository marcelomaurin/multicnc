# Perfis de laser no MultiCNC

Em Configuração, escolha CNC Laser e selecione fabricante e modelo, no mesmo padrão do router e da impressora. O catálogo contém Generic, CUSTOM, GLYPHO, ACMER, SCULPFUN, TwoTrees, Ortur, AtomStack, LONGER e Creality (34 perfis, incluindo o modelo CUSTOM configurável). X e Y continuam editáveis. Os lasers deste catálogo usam foco Z manual, sem curso motorizado cadastrado.

O equipamento salvo em AppData/Maurinsoft/MultiCNC/multicnc.json guarda marca, modelo, conexão e área escolhida. Ao selecionar o nome salvo, o perfil repõe as sugestões de trabalho; ajustes de porcentagem de potência e velocidade não são persistidos pelo cadastro atual. O CUSTOM salva separadamente a potência óptica nominal em watts e as demais especificações informadas. Lasers antigos sem marca/modelo continuam carregando como Generic e preservam a área salva.

## GLYPHO S1

- S1 5W: área 130 × 130 mm informada pelo operador. A expressão do anúncio “5000 W” foi interpretada como 5000 mW = 5 W ópticos. Confirmar na etiqueta do módulo.
- S1 10W modificado: mesma área, potência nominal de 10 W informada pelo operador. Não é apresentado como modelo oficial de fábrica.
- Sensores X/Y conforme descrição fornecida pelo operador. A presença física não confirma que $22 está habilitado.
- Sem documentação oficial GLYPHO localizada: GRBL, 115200 baud/8N1, S máximo 1000 são sugestões compatíveis, não dados certificados da placa. Comprimento de onda fica como não informado até confirmar o módulo.
- Gravação inicial sugerida: 3000 mm/min e 40% no modelo de 5 W; 3000 mm/min e 20% no modificado de 10 W. Essa proporção apenas aproxima a potência nominal; não garante equivalência de resultado.
- Corte: avanço sugerido 600 mm/min, uma passada, sem descida Z automática. Potência inicial igual à de gravação, para teste; não há promessa de corte numa espessura específica.
- Deslocamento sugerido: 5000 mm/min. Não é velocidade máxima certificada.
- Assistência de ar e laser no enquadramento desligados por padrão. O perfil não altera $30, $32, firmware ou qualquer configuração da controladora.
- Os valores são pontos de partida para pequenos testes no próprio material, não receitas de fabricação. O módulo substituído pode ter foco, feixe, alimentação e resposta PWM diferentes.

## Materiais

Madeira, acrílico opaco escuro, couro natural, cortiça, pedra, vidro preparado e papel. Vidro e acrílico transparente não absorvem o diodo azul como a madeira e exigem preparação/processo adequado. Não se promete gravação direta em metal nu nem corte de vidro/pedra. O catálogo não contém parâmetros específicos por material ou espessura.

## Fontes dos modelos padrão

Consultadas em 10/10/2026. Área e potência vêm das páginas abaixo; parâmetros de trabalho/baud são sugestões do software e devem ser conferidos na máquina.

- [ACMER S1: modelos 2.5W, 3.5W e 6W, área 130 × 130 mm](https://acmerlaser.com/products/portable-laser-engraver-mini-machine).
- [ACMER: configuração GRBL/USB e origem inferior esquerda para o S1](https://acmerlaser.com/blogs/users-guidance/acmer-s1-beginners-quick-start-guide). Referência de compatibilidade para a família compacta, sem afirmar identidade com GLYPHO.
- [SCULPFUN S9: 5.5 W e área 410 × 415 mm no catálogo global](https://www.sculpfun.com/products/sculpfun-s9-laser-engraver). Existem revisões anunciadas com Y=420 mm: confira e ajuste.
- [TwoTrees TTS-Pro: catálogo e comparação 5.5/10/20 W](https://twotrees3d.com/products/tts-55-pro-tts-10-pro-diode-laser-engraver-twotrees). TTS-55/10 Pro: 300 × 300 mm; TTS-20 Pro: 418 × 418 mm. Confira a revisão e extensões.
- [Ortur Laser Master 2 Pro S2: opções 5.5W e 10W](https://ortur.net/products/laser-master-2-pro), [área 400 × 400 mm](https://ortur.net/de/pages/support-olm2-pro-s2).
- [AtomStack A5 Pro original: área 410 × 400 mm](https://atomstack.net/products/atomstack-a5-pro-laser-engraving-machine). Não confundir A5 Pro original com A5 Pro V2.

M4 dinâmico pressupõe firmware compatível e modo laser ($32=1); o S máximo escolhido no software deve coincidir com $30. Selecionar um perfil não configura automaticamente esses valores.

## Ampliação comercial pesquisada em 10/10/2026

21 novos perfis. Critério de inclusão: área de gravação XY e potência óptica nominal publicadas em uma fonte do próprio fabricante. A dimensão física da estrutura, o tamanho de uma mesa acessória e o consumo elétrico não substituem essas especificações. As variantes com módulos diferentes são cadastradas separadamente. Os nomes anteriores foram preservados para não quebrar equipamentos salvos.

Os dados publicados são área e potência. Velocidade, percentual de potência, baud e configurações de homing não são certificados por esta pesquisa: permanecem ajustes editáveis do aplicativo. Comprimento de onda não localizado fica como “não informado” nos novos perfis. Sensores só são habilitados quando documentados; a presença deles não configura $22. A URL de origem consta de cada perfil comercial e aparece ao passar o mouse sobre o resumo.

| Fabricante | Modelo | Área XY (mm) | Potência óptica nominal | Fonte |
|---|---|---:|---:|---|
| ACMER | P2 20W | 420 × 400 | 20 W | [Fabricante](https://acmerlaser.com/products/acmer-p2-laser-engraver-cutter-machine) |\n| ACMER | P2 33W | 420 × 400 | 33 W | [Fabricante](https://acmerlaser.com/blogs/news/how-to-use-acmer-laser-cutter-to-cut-acrylic-sheets) |\n| SCULPFUN | S10 10W | 410 × 400 | 10 W | [Fabricante](https://eu.sculpfun.com/en-eu/products/sculpfun-s10-laser-engraver-machine) |\n| SCULPFUN | S30 5W | 410 × 400 | 5 W | [Fabricante](https://www.sculpfun.com/blogs/blog/sculpfun-s30-series) |\n| SCULPFUN | S30 Pro 10W | 410 × 400 | 10 W | [Fabricante](https://www.sculpfun.com/blogs/blog/sculpfun-s30-series) |\n| SCULPFUN | S30 Ultra 11W | 600 × 600 | 11 W | [Fabricante](https://www.sculpfun.com/products/sculpfun-s30-ultra-11w-laser-engraving-machine) |\n| SCULPFUN | S30 Ultra 22W | 590 × 595 | 22 W | [Fabricante](https://www.sculpfun.com/products/sculpfun-s30-ultra-22w-laser-engraving-machine) |\n| SCULPFUN | S30 Ultra 33W | 590 × 595 | 33 W | [Fabricante](https://www.sculpfun.com/products/sculpfun-s30-ultra-33w-laser-engraving-machine) |\n| Ortur | Laser Master 2 Pro S2 1.6W | 400 × 400 | 1.6 W | [Fabricante](https://ortur.net/pages/support-olm2-pro-s2) |\n| Ortur | Laser Master 2 Pro S2 10W | 400 × 400 | 10 W | [Fabricante](https://ortur.net/pages/support-olm2-pro-s2) |\n| Ortur | Laser Master 3 10W | 400 × 400 | 10 W | [Fabricante](https://ortur.net/pages/support-olm3) |\n| Ortur | Laser Master 3 20W | 400 × 380 | 20 W | [Fabricante](https://ortur.net/pages/support-olm3) |\n| Ortur | Laser Master 3 40W | 400 × 380 | 40 W | [Fabricante](https://ortur.net/pages/support-olm3) |\n| LONGER | RAY5 5W | 400 × 400 | 5 W | [Fabricante](https://www.longer3d.com/de/pages/longer-laser-engraver-ray5) |\n| LONGER | RAY5 10W | 400 × 400 | 10 W | [Fabricante](https://www.longer3d.com/products/longer-ray5-10w-laser-engraver) |\n| LONGER | RAY5 20W | 400 × 365 | 20 W | [Fabricante](https://www.longer3d.com/products/longer-ray5-10w-laser-engraver) |\n| Creality | CR-Laser Falcon 5W | 400 × 415 | 5 W | [Fabricante](https://www.crealityfalcon.com/collections/laser-engravers) |\n| Creality | CR-Laser Falcon 10W | 400 × 415 | 10 W | [Fabricante](https://www.crealityfalcon.com/collections/laser-engravers) |\n| Creality | Falcon2 22W | 400 × 415 | 22 W | [Fabricante](https://www.crealityfalcon.com/collections/laser-engravers) |\n| Creality | Falcon2 40W | 400 × 415 | 40 W | [Fabricante](https://www.crealityfalcon.com/collections/laser-engravers) |\n| AtomStack | A20 Pro V2 20W | 400 × 365 | 20 W | [Fabricante](https://jp.atomstack.com/products/atomstack-a20-pro-v2) |\n
A potência do Ortur LM3 foi cadastrada pelo valor nominal do módulo (10/20/40 W); a ficha também publica as faixas de saída. As dimensões do S30 Ultra correspondem à variante no catálogo global consultado, sem extensão.

### Modelos não acrescentados por divergência ou dados incompletos

- AtomStack A10 Pro V2: a própria página global apresenta 400 × 365 mm e 410 × 380 mm para o mesmo nome; não foi escolhida uma medida por suposição.
- TwoTrees TTS-20 Max: páginas oficiais consultadas divergem entre 418 × 418 e 450 × 450 mm; permanece fora até identificar a revisão.
- SCULPFUN S30 Pro Max: a fonte distingue área nominal de 410 × 400 mm e área útil menor dependente dos sensores; não foi acrescentado com um curso presumido.
- Creality Falcon2 Pro: divergência de área entre catálogos regionais; os novos Falcon2 acima são os modelos abertos.
- Modelos CO2/fibra ou de controle proprietário não foram adicionados ao catálogo GRBL de diodo.
- Generic e os dois GLYPHO já solicitados são perfis genérico/personalizados preexistentes; não são contados como modelos comerciais verificados.


## Perfil CUSTOM

Em CNC Laser, escolha fabricante **CUSTOM** e modelo **CUSTOM Laser**.
Informe área X/Y em milímetros e potência óptica real do módulo em watts
(não a potência elétrica consumida). Fabricante, modelo, comprimento de onda
em nm (0 = desconhecido) e presença de interruptores físicos de homing
também podem ser informados. A área inicial 400 × 400 mm é editável;
a potência começa não informada e precisa ser preenchida para salvar.

Dê um nome ao equipamento e use **Save**. Os parâmetros CUSTOM ficam no
cadastro AppData Maurinsoft/MultiCNC/multicnc.json, junto da conexão,
e voltam ao selecionar esse nome. É possível salvar vários equipamentos
CUSTOM com áreas e potências diferentes. Cadastros antigos continuam legíveis.
Os ajustes de processo (velocidades, porcentagem de potência, passes)
continuam disponíveis na interface; este cadastro salva as especificações
da máquina, sem alterar o firmware ou gravar configurações na placa.
