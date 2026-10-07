# Alinhamento da placa

Na etapa Posicionar, selecione e destrave a placa e use Alinhar 2 fiduciais. Informe oito coordenadas separadas por ponto e vírgula:

desenho X1; desenho Y1; medido X1; medido Y1; desenho X2; desenho Y2; medido X2; medido Y2

Use mm e coordenadas do arquivo original. O preparo desconta a origem da placa e considera o espelhamento Bottom. O solver calcula escala uniforme, rotação e translação; X/Y são ajustados para a caixa envolvente após rotação.

Fiduciais coincidentes ou coordenadas não finitas são rejeitados. O alinhamento invalida as trajetórias; atualize o CAM e valide antes de exportar.

A interface ILaserCamera permanece disponível para uma implementação futura. TNoCamera retorna indisponível; a aplicação não simula aquisição de imagem.

Alinhamento e câmera alteram somente a preparação geométrica. Conexão, movimentos e disparo do laser pertencem ao MultiCNC.
