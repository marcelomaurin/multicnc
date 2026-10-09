# 08 — Contratos e dados compartilhados

## Entidades

| Entidade | Conteúdo |
| --- | --- |
| Device | UUID, nome, tipo, marca/modelo, porta serial e referência de perfil |
| MachineProfile | Revisão imutável, firmware, capacidades, parâmetros seriais e envelope |
| MaterialProfile | Material, processo e parâmetros específicos |
| ToolProfile | Ferramenta/bico/feixe e parâmetros pertinentes |
| Project | Documento editável da aplicação autora e suas fontes |
| Job | Pacote imutável de fabricação e metadados |
| Execution | Máquina, sessão, trabalho, perfil efetivo, estado e resultado |
| Event | Identificadores, instante UTC, sequência, severidade e dados |

Marca e modelo são descritivos. A chave de compatibilidade é a combinação de protocolo, versão, pós-processador, capacidades e perfil validado.

## Pacote de trabalho proposto

Extensão `.mcncjob`, contêiner ZIP com caminhos relativos fixos:

```text
manifest.json
program.gcode
profiles/machine.json
profiles/process.json
preview.png              opcional
```

Exemplo ilustrativo de manifesto, sem representar perfil homologado:

```json
{
  "schema_version": "1.0",
  "job_id": "00000000-0000-4000-8000-000000000001",
  "name": "Placa de referência",
  "producer": {"app": "pcb", "version": "0.1.0"},
  "machine_type": "laser",
  "process": "pcb_mask_removal",
  "units": "mm",
  "coordinate_system": {"mode": "absolute", "origin": "stock_lower_left"},
  "bounds_mm": {"min": [0, 0, 0], "max": [100, 80, 0]},
  "required_capabilities": ["laser_modulation"],
  "target": {
    "profile_id": "example-laser",
    "profile_revision": 1,
    "protocol_id": "example-serial-protocol",
    "postprocessor_version": "0.1.0"
  },
  "program": {
    "path": "program.gcode",
    "sha256": "<64 caracteres hexadecimais calculados na exportação>",
    "bytes": 1234
  }
}
```

Os valores `example-*`, tamanho e hash são placeholders documentais. A implementação deverá fornecer JSON Schema e exemplos válidos testáveis; o exemplo acima não deve ser usado como trabalho executável.

Envelope inclui deslocamentos e alturas de segurança, não apenas geometria de corte. Manifesto declarado não é prova suficiente: validar comandos por dialeto suportado, confrontar envelope quando calculável e rejeitar comandos desconhecidos no fluxo normal. Importação de G-code externo é etapa separada, sem presumir a confiabilidade de comentários ou extensões.

## Integridade e importação

Verificar versão do contrato, arquivos obrigatórios, tamanho, hash e compatibilidade antes da fila. Limitar arquivos e tamanho descompactado; rejeitar caminhos absolutos, `..`, links e entradas duplicadas. Nunca executar scripts contidos no pacote. O hash detecta alteração, mas não autentica o autor.

Snapshot de perfis e hashes dos arquivos de perfil devem ser incluídos no contrato executável antes da primeira exportação de produção. Job é imutável: qualquer mudança gera outro identificador e nova validação.

## Mensagens internas

Envelope padrão: `device_id`, `session_id`, `request_id`, `event_sequence`, `timestamp_utc`, `kind`, `payload`. Solicitações não são confirmações. Eventos de resultado fazem referência à solicitação original. Usar relógio monotônico para timeouts, UTC para histórico.

Comandos conceituais: `Connect`, `Disconnect`, `SubmitJob`, `StartJob`, `RequestPause`, `ResumeJob`, `RequestCancel`. Eventos: `ConnectionChanged`, `CapabilitiesDetected`, `JobStateChanged`, `CommandAccepted`, `MachineStatus`, `ProtocolError`, `ExecutionFinished`.

`SubmitJob` pode ser idempotente por chave de submissão. `StartJob` e operações físicas exigem correlação por execução; uma repetição da mensagem não pode iniciar outro trabalho. Reenvio de linhas serial depende exclusivamente do protocolo.

## Persistência e evolução

Cadastros e filas sobrevivem ao reinício; sessões e conexões não. Execuções incompletas são sinalizadas para revisão. Migrações de banco devem ter backup e testes de atualização. Perfis utilizados em execuções anteriores não são sobrescritos.

Contratos usam versão explícita; versão principal desconhecida é recusada. Novos campos opcionais só podem ser ignorados se não alterarem requisitos de execução. Limites de compatibilidade precisam ser parte do esquema e dos testes.
