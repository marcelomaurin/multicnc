# SimuCNC: porta serial virtual

O SimuCNC simula uma impressora 3D com Marlin. Ele recebe G-code pela porta serial, responde como firmware Marlin e atualiza a visualização 3D. O MultiCNC é o controlador cliente.

## Requisito obrigatório

O modo serial entre os dois programas exige um driver de par serial virtual instalado no Windows. O projeto usa o [com0com](https://sourceforge.net/projects/com0com/), que cria duas pontas conectadas:

```text
MultiCNC -> COM3 <-> COM4 <- SimuCNC
```

Sem o driver, `COM3` e `COM4` não existem e o SimuCNC exibirá falha ao abrir a porta.

## Configuração

1. Instale o pacote assinado do com0com como administrador.
2. Confirme no Gerenciador de Dispositivos que as duas portas estão disponíveis.
3. No SimuCNC, informe a porta do simulador, a porta do MultiCNC e o caminho de `setupc.exe`.
4. Use **Criar par virtual**.
5. Inicie o Marlin virtual no SimuCNC.
6. Conecte o MultiCNC na porta correspondente.

O caminho usual do utilitário é `C:\Program Files\com0com\setupc.exe`, mas ele pode variar conforme a instalação.

## Windows 11

A versão 3.0.0.0 do com0com é antiga. Secure Boot e as políticas de assinatura do Windows 11 podem impedir o carregamento do driver. Se as portas aparecerem com código 52 ou não aparecerem no Gerenciador de Dispositivos, o driver não foi aceito pelo sistema. Nesse caso, use uma versão assinada compatível ou um driver de portas virtuais compatível com Windows 11.

## Licença

O com0com é distribuído sob GNU GPL versão 2. Ao redistribuir o instalador ou versões modificadas, mantenha os avisos de copyright, a licença e o acesso ao código-fonte correspondente.
