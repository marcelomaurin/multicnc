# Catalogo de versoes CalculiX — MultiPhysics

Data: 2026-11-09. **Catalogo de candidatos, nao lista de pacotes homologados.**

A versao 2.23 aparece no site oficial https://www.calculix.de/ e ha um pacote Windows x64 comunitario em https://github.com/calculix/CalculiX-Windows/tree/master/releases. A versao 2.22 e alternativa historica. A existencia de um pacote **nao** comprova compatibilidade com os decks MultiPhysics.

Arquivo legivel por maquina: `installer/windows/calculix_catalog.json`. O estado `candidate-unverified` significa que nao ha URL direta, hash SHA-256 confirmado e teste FEM aprovado. **Nao converter candidatos automaticamente em manifestos de instalacao.**

## Para homologar cada entrada

1. Confirmar origem/licenca, URL HTTPS direta, arquitetura, layout do ZIP e dependencias/DLLs.
2. Baixar pacote em ambiente de teste e calcular SHA-256 real; publicar o hash em revisao de codigo.
3. Rodar `ccx -i` em deck pequeno, conferir FRD e comparar com `multiphysics/tests/test_ccx.lpr`.
4. Executar instalacao/rollback/erro de hash e testes em Windows limpo.
5. Somente apos aprovar, criar manifesto de instalacao contendo `version`, `url`, `sha256`, `executable`; preferir um manifesto assinado e mantido pelo projeto.

## Pendencias

- [ ] Homologar CalculiX 2.23 Windows x64.
- [ ] Homologar fallback 2.22 Windows x64.
- [ ] Confirmar distribuicao Linux e suporte ARM.
- [ ] Integrar selecao de versao aprovada no instalador sem solicitar arquivo manual.
- [ ] Proteger contra ZIP path traversal, versoes concorrentes e executar smoke test antes de ativar.
- [ ] Validar instalador Inno Setup e resolver caminho no `FindCCX`.

## Atualizacao 0.2.1

O aplicativo seleciona automaticamente a maior versao numerica aprovada.
O gerenciador aceita `-Action Install -Version 2.23` quando existir uma entrada
aprovada no catalogo; sem entrada aprovada, nao baixa nada. O instalador Inno
continua oferecendo o manifesto manual opcional.

FindCCX consulta a instalacao gerenciada; ZIPs sao inspecionados antes de extrair;
ha lock exclusivo e benchmark numerico antes da ativacao e do rollback.
Os pacotes reais 2.23/2.22 continuam sem homologacao e sem hashes preenchidos.
Ver [ENTREGA_0.2.1.md](ENTREGA_0.2.1.md).
