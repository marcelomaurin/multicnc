# 14 — Registro de validação da primeira versão

Data: 2026-09-28. Plataforma de compilação: Windows x64, Lazarus instalado em `C:\lazarus`, Free Pascal 3.2.2 Win64.

## Executado

- Compilação do projeto `.lpi` pelo `lazbuild`, com LCL Win32: aprovada.
- Script `apps/control/build.ps1 -Test`: aprovado, 40 verificações.
- Testes de parsing de GRBL/Marlin e separação entre coordenadas e contadores de passos.
- Testes de fragmentação e múltiplas linhas, limite de buffer, programa linear e rejeição de códigos fora do subconjunto.
- Testes de persistência e backup do cadastro, e rejeição de porta inválida.
- Duas threads de simulação; pausa de uma sem interromper a outra; cópia independente de snapshots.
- Dois transportes seriais falsos GRBL; envio com acknowledgments, conclusão após Idle e erro isolado.
- Transporte falso Marlin; posição projetada identificada, envio não implementado recusado e firmware desconhecido rejeitado.
- Modo `--smoke`: janela, worker, timer e rastro simulados; imagem renderizada inspecionada.

## Limites da evidência

Não foram abertas portas físicas nem executados movimentos reais. Driver serial, reset por DTR/RTS, firmware comercial, limites mecânicos, resultado do processo e comportamento em falha física continuam pendentes de homologação por equipamento.

O compilador emite avisos de conversão entre strings ANSI/Unicode em algumas mensagens. Eles não impediram a compilação ou os testes; a interface em português foi inspecionada na imagem gerada. A cobertura de interface não inclui todos os diálogos ou configurações de DPI.

O executável gerado não deve ser descrito como homologado para produção. O registro deve ser estendido a cada nova capacidade ou equipamento validado.
