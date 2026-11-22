# Avatares no MultiCAD

## Criar dentro do programa

1. Abra **Avatar → Criar humanoide articulado**.
2. Informe a altura em milímetros; por exemplo, **1800** para 1,80 m.
3. O MultiCAD cria um modelo geométrico de corpo, cabeça, braços, pernas,
   mãos e dedos, com esqueleto e quatro movimentos de demonstração.
4. Na janela de esqueleto, escolha uma animação e clique em **Reproduzir**.
   **Repetir** mantém o ciclo. Desmarcar **Retornar à pose inicial** mantém
   a pose final ao concluir a animação.
5. Salve as alterações no projeto e grave o arquivo `.mcad`.

A criação do humanoide é local e não consome créditos de IA. A aparência é
geométrica; não gera uma pessoa fotorrealista. O projeto guarda malha,
esqueleto, vínculos, script e biblioteca de animações.

## Usar os avatares do Assistente

Abra **Avatar → Importar avatar do Assistente / glTF** e selecione
`AVATARES/professor/avatar.json`, `AVATARES/robo/avatar.json`, outro
`avatar.json`, ou o respectivo `modelo.gltf`. Arquivos GLB 2.0 também são aceitos.

Os modelos não precisam ser copiados para o repositório do MultiCNC. Após a
importação e o salvamento, os dados necessários ficam incorporados ao `.mcad`.
Buffers externos devem ficar na pasta do modelo; caminhos para fora dessa pasta
e downloads por URL não são aceitos pelo importador.

A importação preserva os pesos originais de até quatro ossos por vértice,
as matrizes de vínculo, as orientações de repouso e os clips de rotação e
translação. Professor, Robô e Businesswoman do Assistente foram verificados
com seus 163 ossos e 65 animações. A exibição usa a aparência CAD do documento;
texturas e materiais originais glTF não são reproduzidos.

Cada eixo continua sendo um segmento independente. Para representar um osso
com rotação XYZ, o MultiCAD encadeia segmentos Z/Y/X no mesmo pivô. Os canais
de deslocamento vêm antes dos canais de rotação. Os IDs originais dos ossos
continuam disponíveis para os pesos e para os movimentos do Assistente.
O limite é de 2048 segmentos, equivalente a até 341 nós glTF com seis canais.

Os clips ficam na lista **Animação**. São armazenados de forma comprimida;
somente o movimento selecionado precisa ser descomprimido para reprodução.
São aceitos movimentos `assistente-motion` v1 e v2, inclusive `rotation_deg`
XYZ. Rotações XYZ usam interpolação de quaternions. Translações usam
milímetros, `channel: "translation"`, `axis: "xyz"` e `position_mm`.

## Alturas e proporções

glTF usa metros; a importação converte uma única vez para milímetros.
Não se deve normalizar separadamente roupas, cabeça ou membros.

Na importação, o programa apresenta largura, altura e profundidade reais.
O campo de altura começa com a medida original. **Apoiar a base no chão**
alinha a menor coordenada Y a zero. Para mudar a medida depois, use
**Avatar → Ajustar altura do avatar**.

O ajuste é uniforme: aplica o mesmo fator à malha, aos pivôs, às extremidades,
aos pontos de vínculo e aos deslocamentos das animações. Os ângulos não mudam.
Assim, um avatar reduzido pela metade continua movimentando braços, roupas
e pés na mesma proporção.

Em **Gerar 3D por texto**, escolha a referência da medida: maior dimensão,
altura, largura ou profundidade. Arquivos antigos continuam usando a maior
dimensão. Uma peça com largura quatro vezes maior que a altura, ajustada pela
maior dimensão para 1800 mm, terá 450 mm de altura; ajustada por **Altura**,
terá efetivamente 1800 mm de altura, preservando a proporção 4:1.

## Controlar pelo Pascal

```pascal
begin
  IniciarSimultaneo;
  MoverArticulacao('upperarm01.L', 'z', 65, 800);
  MoverArticulacao('upperarm01.R', 'z', -65, 800);
  FinalizarSimultaneo;
  Esperar(400);
  MoverDeslocamento('root', 'z', 100, 1000);
end.
```

`MoverArticulacao` recebe osso, eixo, graus e duração. `DefinirArticulacao`
atribui um ângulo no instante atual. `MoverDeslocamento` usa milímetros.
`MoverSegmento` continua aceitando o ID específico de qualquer segmento.
As chamadas normais são sequenciais; dentro de um grupo simultâneo, começam
no mesmo instante. Ao fechar o grupo, o tempo avança até o movimento mais longo.
Não são aceitos grupos aninhados ou dois movimentos do mesmo canal no mesmo grupo.

## Ajustar com IA

Em **Criar esqueleto com IA**, configure seu endpoint/modelo e descreva o ajuste.
Sem esqueleto, a IA propõe uma hierarquia nova a partir da geometria. Com um
esqueleto existente, recebe os ossos e os eixos disponíveis e retorna ajustes
`multicad-rig-edit`, mantendo IDs, hierarquia, pesos e biblioteca de movimentos.
Os ajustes podem alterar ângulo, limites e posição do pivô/extremidade. Pivôs
de um mesmo osso são alterados em conjunto para manter os eixos coincidentes.

A proposta é validada antes de substituir a prévia. Ossos vinculados à malha
não podem desaparecer. Cancelar a janela mantém o documento original.
Os testes de IA usam respostas e servidor local simulados; não foi feita uma
chamada a um provedor pago para validar esta versão.

## Verificação e limites

`test_avatar.lpi` cobre geração, alturas relativas, quatro pesos por vértice,
GLB/glTF, base de rotação, translação com escala de pai, persistência,
ajustes de IA e temporização Pascal. O fixture possui valores esperados de
deformação calculados independentemente do código Pascal.
`test_avatar_ui.lpi` verifica criação, altura solicitada, seleção/reprodução,
enquadramento inicial, isolamento da prévia, salvamento e redimensionamento.

O importador aceita triângulos, escala uniforme e animações LINEAR. Aplique
escalas não uniformes no editor de origem antes de importar o esqueleto. Converta accessors sparse,
compressões/extensões obrigatórias e animações STEP/CUBICSPLINE antes de importar.
Canais animados de escala e morph não são reproduzidos; quando presentes,
o importador informa essa limitação. A edição aplica limites por eixo;
não implementa detecção de colisão, equilíbrio físico ou IK dos pés.
