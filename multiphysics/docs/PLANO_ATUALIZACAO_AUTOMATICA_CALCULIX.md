# Pacote de atualização automática do CalculiX — MultiPhysics

Data: 2026-11-09 | Estado: PENDENTE | Prioridade: P1 | Referência: issue #16

## Objetivo
Adicionar ao MultiPhysics e ao instalador MultiSuite um gerenciador opcional que detecta, baixa, verifica, instala e atualiza o CalculiX CrunchiX (ccx) sem exigir instalação manual. O solver interno continua independente e funcional offline.

## Escopo do pacote de atualização
- Interface: Configurações > Motores de simulação > CalculiX: Detectar, Instalar, Verificar atualizações, Atualizar e Restaurar versão anterior.
- Inicialização: detectar CALCULIX_EXE, configuração persistida e instalação gerenciada; mostrar versão, caminho e status sem alterar instalações externas automaticamente.
- Catálogo de versões: manifesto versionado mantido pelo projeto com plataforma, arquitetura, URL oficial/autorizada, licença, SHA-256 e dependências. Não usar URL fixa não verificada ou baixar binários de fonte desconhecida.
- Download: HTTPS, timeout, progresso, cancelamento, retomada quando suportada, hash SHA-256 obrigatório, verificação de assinatura quando disponível; bloquear falhas de integridade.
- Instalação: extrair em diretório isolado por versão; verificar DLLs/runtime e licença; executar teste mínimo com entrada conhecida; ativar somente após sucesso.
- Atualização: verificar sob demanda e opcionalmente em intervalo configurável, com consentimento antes de baixar/alterar; nunca atualizar durante simulação; preservar versão anterior e fazer rollback atômico em falha.
- Integração Lazarus: módulo Free Pascal para gerenciar manifesto, downloads, verificação e configuração do caminho do ccx; usar TProcess para teste e execução, sem bloquear UI.
- Distribuição: instalador oferece caixa opcional “Baixar e configurar CalculiX”; sem internet ou com recusa, continuar instalação com solver interno. Ngspice é tarefa futura separada e não deve ser baixado sem integração funcional.
- Auditoria: registrar data, versão anterior/nova, URL de origem, hash, consentimento, tempo, saída de teste e erros em log sem dados sensíveis.

## Pendências de implementação
- [ ] AUD-CCX-01: inventariar integração atual em multiphysics_ccx.pas, testes e instalador, incluindo descoberta de CALCULIX_EXE.
- [ ] AUD-CCX-02: definir catálogo/manifesto assinado ou confiável e política de versões suportadas por Windows/Linux/arquitetura.
- [ ] AUD-CCX-03: implementar downloader com validação de SHA-256, timeout, cancelamento e erros de rede.
- [ ] AUD-CCX-04: implementar instalação lado a lado, ativação transacional e rollback.
- [ ] AUD-CCX-05: criar tela de status e atualização no MultiPhysics; configurar consentimento e frequência.
- [ ] AUD-CCX-06: integrar opção ao instalador Windows sem tornar CalculiX obrigatório.
- [ ] AUD-CCX-07: validar licenças, redistribuição e dependências de cada pacote antes de publicar downloads.
- [ ] AUD-CCX-08: criar testes automáticos de versão atual, desatualizada, offline, hash incorreto, download interrompido, DLL ausente, rollback e concorrência com simulação.
- [ ] AUD-CCX-09: testar execução de benchmark FEM real após instalar/atualizar e documentar compatibilidade.
- [ ] AUD-CCX-10: atualizar MANUAL.md, RUNTIME.md e notas de versão após implementação.

## Critérios de aceite
1. Usuário instala/atualiza CalculiX por opção explícita, sem operações manuais de ZIP, PATH ou DLL.
2. Falhas de rede, licença, hash ou teste não alteram a versão ativa; logs permitem diagnóstico.
3. Instalação offline e solver interno continuam funcionando.
4. Versão, origem e resultado do autoteste são visíveis; rollback funciona.
5. Pipeline automatizado cobre casos positivos e negativos; teste com CalculiX real não é marcado como aprovado quando ausente.

## Entrega e limites
Este arquivo é o **pacote de especificação e pendências**, não um atualizador executável. Implementação, build, testes e distribuição permanecem pendentes. Vincular à issue #16 e não declarar a atualização automática como concluída até passar nos critérios acima.

## Avanço de implementação — PR #18 (2026-11-09)
- Verificador offline em `multiphysics/tools/verify_ccx_package.py`: SHA-256 obrigatório, inspeção de ZIP e bloqueio de caminhos perigosos, links simbólicos e múltiplos executáveis.
- Testes unitários adicionados em `multiphysics/tools/test_verify_ccx_package.py`: cenários de hash incorreto, ZIP corrompido, path traversal, executável ausente/duplicado e pacote estruturalmente válido.
- Executar testes: `cd multiphysics/tools && python -m unittest -v test_verify_ccx_package.py`.
- O resultado `VERIFICADO_PARA_INSPECAO` **não** significa pacote homologado ou seguro para ativação; testes reais em Windows, assinatura/proveniência, DLLs e licença continuam necessários.
- **Status**: alterações em branch de desenvolvimento, sem aprovação de instalação automática em produção.
