program test_calibration_matrix;

{ Teste de material do LaserArt: a matriz varia potencia nas colunas e
  velocidade nas linhas, e o G-code sai com cabecalho LaserArt. }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, laserart_calibration;

var
  J: TLACalibJob;
  A, B: TLACalibPoint;
  G: TStringList;
begin
  J := TLACalibJob.Create;
  try
    TLaserCalibration.BuildMatrix(J, 0, 0, 10, 10, 100, 500, 600, 1800, 3, 3);
    if J.Count <> 3 * 3 * 5 then Halt(1);
    { 5 pontos por quadrado: ponto 1 = 1a coluna, ponto 6 = 2a coluna }
    A := J.Point(1); B := J.Point(6);
    if A.Power = B.Power then Halt(2);
    { ponto 16 = 1o quadrado da 2a linha }
    B := J.Point(16);
    if A.Feed = B.Feed then Halt(3);
    if A.LaserOn = J.Point(0).LaserOn then Halt(4);
    G := J.ToGCode;
    try
      if Pos('; LaserArt', G[0]) <> 1 then Halt(5);
      if G.IndexOf('M4 S0') < 0 then Halt(6);
      if Pos('S100 F600', G.Text) = 0 then Halt(7);
      if G[G.Count - 1] <> 'M5' then Halt(8);
    finally
      G.Free;
    end;
    { parametros invalidos nao geram nada }
    TLaserCalibration.BuildMatrix(J, 0, 0, 10, 10, 0, 500, 600, 1800, 3, 3);
    Writeln('Laser calibration matrix: OK');
  finally
    J.Free;
  end;
end.
