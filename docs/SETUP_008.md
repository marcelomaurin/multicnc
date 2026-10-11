# Setup 008 — MultiSuite 0.08

Gerado em **11/10/2026**, para **Windows x64**, com **MultiCAD 0.0.8.0**.

[Baixar setup_multcnc_008.exe](../setup/setup_multcnc_008.exe) · [Cópia em bin](../bin/setup_multcnc_008.exe) · [SHA256SUMS](../setup/SHA256SUMS)

## Conteúdo

O pacote mantém os 13 aplicativos e a interface do instalador 007. Atualiza o MultiCAD para a versão 008, incluindo seleção e visualização de esboços, extrusão e corte, cota inteligente horizontal/vertical/alinhada, referências a esboços anteriores, sincronização do painel de propriedades com a ferramenta ativa e registro em AppData/Maurinsoft/MultiCAD/multicad.log.

As demais aplicações foram compiladas a partir dos fontes registrados no mesmo commit. Alterações locais ainda não registradas no LaserPCB e MakePCB não fazem parte deste pacote.

## Verificação

Os 13 executáveis compilaram. A bateria de console registrou **86 testes aprovados e zero falhas**; 1 teste de integração TCP foi omitido porque exige o SimuCNC em execução. Os sete testes do empacotamento passaram. As regressões do MultiCAD já foram verificadas antes da publicação da tag multicad-008, incluindo 568 verificações do núcleo e 23 verificações da interface, além dos testes específicos de cota, seleção, extrusão, corte e cancelamento de plano.

O pacote inclui build-manifest.json e qa-tests.json. Cópias para consulta: [manifesto](../setup/build-manifest-008.json) e [testes](../setup/qa-tests-008.json). O manifesto registra o commit **a2098a2cfa1547c5237cb1eeaeb25347bba512bb**, com **source_dirty=false**, e valida a arquitetura amd64 e os hashes dos arquivos distribuídos. Os executáveis do instalador tiveram apenas os símbolos de depuração removidos.

Não foi realizada instalação automática neste computador.

SHA-256 do instalador:

```text
daabdc4532ae0a039ae773d65bfc2cbe35ddab762a914d023a027c7f1d06f3b4  setup_multcnc_008.exe
```
