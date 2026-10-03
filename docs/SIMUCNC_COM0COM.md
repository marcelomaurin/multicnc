# SimuCNC: conexão serial física ou virtual

O SimuCNC simula uma impressora 3D com Marlin. Ele recebe G-code pela porta serial, responde como firmware Marlin e atualiza a visualização 3D. O MultiCNC é o controlador cliente.

## Requisito obrigatório

É necessária uma ligação serial funcional entre duas portas distintas: uma para
o MultiCNC e outra para o SimuCNC. Há duas opções:

- Dois adaptadores USB–serial ligados por cabo cruzado.
- Um par de portas virtuais criado por um driver compatível com o Windows.

**O com0com não é obrigatório ao usar adaptadores físicos.** Nesse caso, apenas
os drivers dos próprios adaptadores precisam estar instalados e funcionando.

## Opção 1: dois adaptadores USB–serial cruzados

```text
MultiCNC -> COM do adaptador A -> cabo cruzado -> COM do adaptador B -> SimuCNC
```

### Ligação elétrica

Para adaptadores USB–TTL com níveis elétricos compatíveis:

| Adaptador A (MultiCNC) | Adaptador B (SimuCNC) |
|---|---|
| TX | RX |
| RX | TX |
| GND | GND |

**Não conecte os pinos VCC dos adaptadores.** Ambos recebem alimentação pela USB.
Confira as especificações dos adaptadores: não misture TTL com RS-232, nem níveis
TTL incompatíveis. Para dois adaptadores RS-232, use um cabo null-modem com
pinagem adequada aos conectores; não aplique a pinagem de um módulo TTL ao DB9.

#### Instalação e configuração do com0com dos programas

1. Conecte ambos os adaptadores ao computador e identifique suas portas no
   Gerenciador de Dispositivos. COM3 e COM4 são apenas exemplos.
2. No SimuCNC, informe a COM do adaptador B no campo da porta serial e clique em
   **Iniciar Marlin**. Ignore os campos de criação do par e do `setupc.exe`;
   **não clique em Criar par virtual**.
3. No MultiCNC, selecione **Impressora 3D**, protocolo **Marlin**, a COM do
   adaptador A e clique em **Conectar equipamento**.
4. Configure ambos com o mesmo baud rate, por exemplo **115200**, **8 bits de
   dados, sem paridade, 1 bit de parada (8N1)** e sem controle de fluxo.
5. Para verificar a ligação, envie `M115` seguido de fim de linha pelo controlador
   ou por um terminal serial. O log do SimuCNC deve registrar RX e TX. Feche o
   terminal antes de reconectar o MultiCNC, pois ele ocupa a mesma porta.
6. Depois de validar a troca de comandos e respostas, envie o G-code pelo
   MultiCNC e acompanhe os movimentos no SimuCNC. Extrusão aparece quando o
   comando e o estado térmico simulado permitem depositar material.

Se não houver comunicação, confira as COMs, TX/RX cruzados, GND, parâmetros
seriais e se outro programa está ocupando uma das portas. Esta documentação
descreve a montagem; o teste físico com os adaptadores ainda precisa ser realizado.

## Opção 2: par virtual com com0com

O [com0com](https://sourceforge.net/projects/com0com/) cria duas pontas conectadas,
sem adaptadores físicos:

```text
MultiCNC -> COM3 <-> COM4 <- SimuCNC
```

O botão **Criar par virtual** do SimuCNC usa especificamente o com0com. Ter o
`setupc.exe` instalado não garante que o driver esteja carregado ou que as COMs
possam ser abertas. Veja as limitações do Windows 11 abaixo.

## Configuração

1. Instale o pacote assinado do com0com como administrador.
2. Localize o `setupc.exe` instalado. Execute o SimuCNC como administrador para criar o par.
3. No SimuCNC, informe a porta do simulador, a porta do MultiCNC e o caminho de `setupc.exe`.
4. Use **Criar par virtual**.
5. Confirme que as portas estão disponíveis e sem erro no Gerenciador de Dispositivos; então inicie o Marlin no SimuCNC.
6. Conecte o MultiCNC na porta correspondente.

O caminho usual do utilitário é `C:\Program Files (x86)\com0com\setupc.exe`, mas ele pode variar conforme a instalação.

## Windows 11 e erros do com0com

A versão 3.0.0.0 do com0com é antiga. Secure Boot e as políticas de assinatura do Windows 11 podem impedir o carregamento do driver. Se as portas aparecerem com código 52 ou não aparecerem no Gerenciador de Dispositivos, o driver não foi aceito pelo sistema. Nesse caso, use uma versão assinada compatível ou um driver de portas virtuais compatível com Windows 11.

## Licença

O com0com é distribuído sob GNU GPL versão 2. Ao redistribuir o instalador ou versões modificadas, mantenha os avisos de copyright, a licença e o acesso ao código-fonte correspondente.

O erro **740** exige elevação administrativa para executar o utilitário. O **Código 52** indica bloqueio da assinatura do driver; executar como administrador não resolve esse bloqueio. Na máquina usada neste projeto, o pacote com0com 3.0.0.0 apresentou Código 52. A ligação com dois adaptadores físicos dispensa esse driver.
