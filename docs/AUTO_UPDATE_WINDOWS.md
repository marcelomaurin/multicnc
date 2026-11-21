# Atualizacao automatica da MultiSuite (Windows)

O instalador Windows inclui o verificador `multisuite_updater.ps1`. A opcao **Verificar atualizacoes automaticamente ao iniciar o Windows** registra o comando na inicializacao do usuario (HKCU Run). O processo consulta `releases/latest` do GitHub, compara a tag com a versao do instalador, descarrega o setup e o arquivo `SHA256SUMS`, valida o SHA-256 e inicia o instalador do Inno Setup.

## Publicacao necessaria

1. Execute os testes e compile o setup de release para Windows.
2. Crie uma **GitHub Release publicada, nao draft e nao pre-release**, com tag numerica maior que a anterior (ex.: `v0.19`).
3. Anexe o instalador com nome `setup_multcnc_0.19.exe` (ou `setup_multcnc_019.exe`) e `SHA256SUMS` contendo a linha SHA256 do mesmo arquivo.
4. A versao `MyAppVersion` gerada no instalador deve coincidir com a tag. Apenas commits/branches sem uma Release nao acionam atualizacoes.

## Comportamento e limites

- A verificacao ocorre na entrada do Windows, no maximo uma vez por 12 horas com rede disponivel. Nao roda continuamente.
- O instalador novo abre **interativamente** para respeitar selecao de modulos e solicitacoes UAC; nao ha atualizacao totalmente silenciosa.
- O Inno Setup coordena fechamento dos aplicativos em uso. Nao atualizar durante movimentos de CNC, laser ou impressora 3D; concluir o trabalho antes de aceitar a instalacao.
- O checksum detecta corrupcao, mas nao substitui assinatura digital de codigo ou um manifesto assinado. Para uso amplo, recomenda-se assinatura Authenticode.
- O script registra falhas em `%LOCALAPPDATA%\MultiSuite\Updater\updater.log`.
- Teste manual: `powershell -NoProfile -File "C:\Program Files\MultiSuite\multisuite_updater.ps1" -InstalledVersion "0.18" -ForceCheck`.
- Linux e ARM ainda requerem outro instalador e estrategia de atualizacao; este mecanismo e exclusivo do pacote Windows.

O resultado so entra nas instalacoes apos integrar a branch e gerar/publicar um novo instalador.
## Pipeline unificado (09/11/2026)

`windows-installer.yml` e o unico workflow que publica instaladores por tag.
O workflow duplicado `multisuite-windows-installer.yml` foi removido. Tags
aceitam de dois a quatro numeros (`v0.19`, `v0.19.1`, `v0.19.1.0`). O build
publica o nome por versao e seu SHA-256; a Release so sai de draft depois
que ambos os uploads terminam. Reexecucoes substituem esses assets.

Versoes equivalentes (`0.19`, `0.19.0`, `0.19.0.0`) nao causam reinstalacao.
Quando ha aliases, o atualizador prefere o nome que coincide com a versao.
`-CheckOnly` consulta sem baixar ou abrir instalador, por exemplo:

```powershell
powershell -NoProfile -File multisuite_updater.ps1 -InstalledVersion 0.18 -CheckOnly
```

`tools/test_windows_updater.py` executa o script PowerShell com rede e processo
substituidos por fixtures: versao equivalente, checksum incorreto, origem
incorreta, consulta sem download e download/verificacao/abertura. Isso nao
substitui o ensaio entre duas Releases reais nem a instalacao com UAC.
