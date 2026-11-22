# Esqueleto e movimentos

Abra **Ferramentas → Esqueleto e movimentos**. O editor trabalha sobre uma
cópia: **Salvar no projeto** aplica a alteração; **Cancelar** mantém o projeto
aberto. Depois, salve o `.mcad` normalmente. Desfazer/refazer também inclui o
esqueleto, a pose, o movimento importado e o script.

Para experimentar, abra `multicad/examples/robo-articulado.mcad`. O exemplo
contém três corpos, três juntas e um script Pascal. Na aba **Script Pascal**,
clique em **Reproduzir Pascal**.

## Segmentos

Cada segmento tem ID persistente, nome, pai, pivô, extremidade, um eixo de
rotação X/Y/Z e limites mínimo/máximo. Coordenadas são absolutas na pose
original, em milímetros; Y aponta para cima. O eixo acompanha a rotação do
pai. O filho acompanha o movimento dos ancestrais. Para uma articulação com
mais graus de liberdade, encadeie segmentos com o mesmo pivô e eixos distintos.

**Novo segmento** usa como pai o segmento selecionado. Edite os campos e
clique em **Aplicar segmento**. O campo **Ângulo da pose** atualiza a prévia.
O editor recusa ciclos, pais inexistentes, IDs/nomes ambíguos e ângulos fora
dos limites. Um pai com filhos não pode ser removido antes de reorganizar os filhos.

O vínculo automático usa a distância dos vértices aos ossos. A transição
entre pai e filho usa pesos normalizados; membros sem relação de parentesco
não se misturam. Para vincular uma parte rígida, informe nomes/prefixos de
faces CAD separados por `;`, por exemplo `Braco/;Mao/`. Esses vínculos têm
precedência. Os ossos aparecem em azul e os pivôs em amarelo.

A deformação ocorre em cópias da malha, dentro da prévia. A geometria CAD
original, as operações, as propriedades de massa e os exportadores CAD
continuam usando a peça original. Não é um editor de pesos por vértice nem
um simulador de colisões ou dinâmica.

## Pascal

O editor usa o compilador **Pascal Script** distribuído com o Lazarus.
Variáveis, condições e laços Pascal funcionam. O script gera uma sequência
temporal; não bloqueia a interface esperando cada movimento.

```pascal
var I: Integer;
begin
  for I := 1 to 2 do
  begin
    MoverSegmento('braco', 45, 600);
    Esperar(300);
    MoverSegmento('braco', 0, 600);
  end;
end.
```

| Comando | Comportamento |
|---|---|
| `DefinirAngulo(Segmento, Graus)` | Define o ângulo no instante atual. |
| `MoverSegmento(Segmento, Graus, DuracaoMS)` | Interpola até o alvo e avança o tempo da sequência. |
| `Esperar(DuracaoMS)` | Mantém a pose durante o intervalo. |
| `Angulo(Segmento)` | Consulta o ângulo corrente na montagem da sequência. |
| `TotalSegmentos` | Consulta a quantidade de segmentos. |
| `Segmento(Indice)` | Retorna o ID; o primeiro índice é zero. |

**Testar** compila e verifica a sequência. **Reproduzir Pascal** executa a
prévia; **Parar** restaura a pose anterior. A duração máxima é de dez minutos.
Há limites de instruções, tempo de execução e quantidade de quadros. A API
de scripts expõe apenas os comandos de movimento, sem operações de arquivo
ou rede. Erros de compilação, segmentos desconhecidos ou limites de junta
não alteram a pose do documento.

## Movimentos do Assistente

**Importar movimento** lê JSON `assistente-motion` versões 1 e 2: `tracks`, `bone`,
`axis` e `keyframes` com `time_ms` e `angle`. Os nomes dos ossos precisam
corresponder ao ID ou nome de um segmento. O eixo de cada trilha precisa
coincidir com o eixo da junta. Ossos desconhecidos ou eixos incompatíveis
geram um diagnóstico; não são descartados silenciosamente.

Há suporte a interpolação linear/smoothstep, repetição e retorno à pose base.
**Reproduzir importado** usa o movimento gravado no projeto. **Importar/
exportar esqueleto** troca o JSON `multicad-rig` versão 1, também editável
pela aba **JSON do esqueleto**. O menu **Avatar** importa o rig e os movimentos de GLB/glTF e de `avatar.json`
do Assistente. FBX não é suportado. Veja [Gerar avatares](GERAR_AVATARES.md).

## Criação com IA

Em **Configuração da IA**, configure a seção **IA do esqueleto**:

- Endpoint de chat compatível com OpenAI/Ollama. O endereço inicial é
  `http://127.0.0.1:8095/v1/chat/completions`.
- Nome exato do modelo disponível no servidor.
- Chave, se o servidor exigir. No Windows, a chave fica protegida por DPAPI;
  no Linux, uma chave digitada vale para a sessão. Também são lidas as variáveis
  `MULTICAD_RIG_ENDPOINT`, `MULTICAD_RIG_MODEL` e `MULTICAD_RIG_KEY`.

Na aba **Criar esqueleto com IA**, descreva o objeto, a pose e quais partes
devem se mover. **Gerar proposta** envia a descrição, as dimensões e até 256
vértices amostrados por corpo ao servidor configurado. O servidor pode ser
local ou remoto; um serviço remoto pode consumir créditos. Não é usada a
chave Meshy para o modelo de linguagem.

A resposta precisa conter uma hierarquia `multicad-rig` válida. A proposta é
aplicada à cópia do editor, exibida sobre a malha e permanece editável antes
de **Salvar no projeto**. A IA não executa scripts retornados na resposta.
Não há garantia de identificação anatômica correta em uma malha arbitrária:
confira os pivôs, a associação da geometria e os limites no editor.

## Compilar e verificar

O caminho `$(LazarusDir)/components/PascalScript/Source` está nos projetos
do aplicativo e dos novos testes. No Linux, instale também as unidades de
rede do FPC e as dependências já usadas pela geração 3D.

```sh
lazbuild --ws=nogui multicad/tests/test_rig_motion.lpi
multicad/tests/test_rig_motion
lazbuild --ws=gtk2 multicad/src/app/multicad.lpi
lazbuild --ws=gtk2 multicad/tests/test_rig_ui.lpi
MULTICAD_KERNEL=pascal xvfb-run -a multicad/tests/test_rig_ui
```

Os testes verificam hierarquia, pivôs, eixo, limites, deformação sem alterar
a malha original, execução Pascal, interrupção de laço infinito, formato do
Assistente, persistência transacional e validação da resposta da IA. O teste
da interface verifica prévia, reprodução, inclusão de segmento, Cancelar e
Salvar. A workflow **MultiCAD Rig and Motion** executa em Linux/Windows e
disponibiliza os executáveis como artefatos.
