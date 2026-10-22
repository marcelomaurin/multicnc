# Regras A01 a A08

As regras propõem tarefas Sugeridas e nunca executam ferramentas ou máquinas.
As alterações são preparadas em uma cópia do documento e aplicadas como um único
passo de desfazer. Erros de geração ou decisão não aplicam parte da mudança.

## Identidade e origem

`origin` grava `by=rule`, `rule`, `scope` (subsistema) e `sources` (IDs estáveis).
A identidade é regra + tipo de saída + origens ordenadas. O tipo distingue
fabricação e compra de A02. Na cadeia de A06, cada saída tem origens próprias.
Cancelar uma sugestão mantém essa identidade para que ela não seja oferecida de novo.

## Prontidão e geração em etapas

A01/A02 podem propor fabricação antes do projeto ficar pronto. A03/A04 exigem
predecessoras em revisão ou concluídas, com artefato válido quando exigido. A05
exige validação concluída e todos os critérios aprovados ou dispensados. A06 espera
fabricações concluídas; o marco final espera o teste funcional aprovado.

Gravação especificada em `gravacao` vira uma tarefa A01 encadeada depois da
fabricação da peça. A03 reúne projetos diretos de cada resumo e as montagens de
seus subsistemas. Um único resumo que contém todo o projeto não cria uma segunda
montagem idêntica do objetivo.

A validação recebe as especificações e os critérios dos projetos, e sugere os
estudos pela carga, temperatura, rotação e tensão/corrente. O checklist de montagem
física lê `manual_steps` do arquivo MultiAssembly vinculado, preserva a origem e
acrescenta um vínculo de artefato para detectar mudanças posteriores do manual.

## Liberação

`options.fabrication_gate` vem ligado. A fabricação sugerida por regra não pode
começar sem um marco A05 concluído em suas predecessoras. Aceitar a liberação
acrescenta vínculos às fabricações planejadas do escopo correspondente; uma
fabricação encadeada, como a gravação, herda a liberação pela predecessora.
Desligar o gate remove seus vínculos futuros; tarefas em andamento e concluídas
são preservadas. `options.rules` permite habilitar as regras por projeto no JSON.

## Revisão e modelos

Critério reprovado de validação/teste usa `revisar_tarefa` para indicar a peça ou
placa. A07 cria uma tarefa nova com a evidência, sem aresta de retorno nem alteração
dos trabalhos anteriores. Uma origem inexistente recusa a geração inteira.

Ao criar de modelo, o novo projeto remapeia tarefas, vínculos, atribuições e origens.
Limpa arquivos de entrega, estados reais, critérios aprovados e dados de progresso.
Os exemplos distribuídos estão planejados e não representam trabalho real concluído.
