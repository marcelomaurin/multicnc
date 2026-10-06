unit laserart_calibration;

{ Teste de material do LaserArt: matriz de quadrados variando a potencia
  (colunas) e a velocidade (linhas), com gerador de G-code proprio.

  Potencia em valor S (0..S max do GRBL). O arquivo traz o cabecalho
  "; LaserArt", entao o MultiCNC abre direto em CNC Laser. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, multisuite_numfmt;

type
  TLACalibPoint = record
    X, Y: Double;
    LaserOn: Boolean;
    Power, Feed: Double;
  end;

  TLACalibJob = class
  private
    FPoints: array of TLACalibPoint;
  public
    procedure Clear;
    procedure Add(X, Y: Double; LaserOn: Boolean; Power, Feed: Double);
    function Count: Integer;
    function Point(I: Integer): TLACalibPoint;
    function ToGCode(UseM3: Boolean = False): TStringList;
    procedure SaveGCode(const FileName: string; UseM3: Boolean = False);
  end;

  TLaserCalibration = class
  public
    class procedure BuildMatrix(J: TLACalibJob; X0, Y0, CellW, CellH,
      PowerMin, PowerMax, FeedMin, FeedMax: Double; Cols, Rows: Integer);
  end;

implementation

procedure TLACalibJob.Clear;
begin
  SetLength(FPoints, 0);
end;

procedure TLACalibJob.Add(X, Y: Double; LaserOn: Boolean; Power, Feed: Double);
var
  N: Integer;
begin
  N := Length(FPoints);
  SetLength(FPoints, N + 1);
  FPoints[N].X := X;
  FPoints[N].Y := Y;
  FPoints[N].LaserOn := LaserOn;
  FPoints[N].Power := Power;
  FPoints[N].Feed := Feed;
end;

function TLACalibJob.Count: Integer;
begin
  Result := Length(FPoints);
end;

function TLACalibJob.Point(I: Integer): TLACalibPoint;
begin
  Result := FPoints[I];
end;

function TLACalibJob.ToGCode(UseM3: Boolean): TStringList;
var
  I: Integer;
  P: TLACalibPoint;
  LastS, LastF: Double;
  MCode: string;
begin
  Result := TStringList.Create;
  if UseM3 then MCode := 'M3' else MCode := 'M4';
  Result.Add('; LaserArt -> MultiCNC');
  Result.Add('; Teste de material: potencia (colunas) x velocidade (linhas)');
  Result.Add('; MultiCNC: mantenha "Pass count" = 1 e "Override file feed rates" desligado.');
  Result.Add('G21');
  Result.Add('G90');
  Result.Add('M5');
  Result.Add(MCode + ' S0');
  LastS := -1;
  LastF := -1;
  for I := 0 to High(FPoints) do
  begin
    P := FPoints[I];
    if P.LaserOn then
    begin
      if (P.Power <= 0) or (P.Feed <= 0) then
        raise Exception.Create('Potencia/velocidade nao calibradas no ponto ' + IntToStr(I));
      if (P.Power <> LastS) or (P.Feed <> LastF) then
        Result.Add(Format('G1 X%.3f Y%.3f S%.0f F%.0f', [P.X, P.Y, P.Power, P.Feed], InvariantFS))
      else
        Result.Add(Format('G1 X%.3f Y%.3f', [P.X, P.Y], InvariantFS));
      LastS := P.Power;
      LastF := P.Feed;
    end
    else
    begin
      Result.Add(Format('G0 X%.3f Y%.3f S0', [P.X, P.Y], InvariantFS));
      LastS := 0;
    end;
  end;
  Result.Add('M5');
end;

procedure TLACalibJob.SaveGCode(const FileName: string; UseM3: Boolean);
var
  G: TStringList;
begin
  G := ToGCode(UseM3);
  try
    G.SaveToFile(FileName);
  finally
    G.Free;
  end;
end;

class procedure TLaserCalibration.BuildMatrix(J: TLACalibJob; X0, Y0, CellW, CellH,
  PowerMin, PowerMax, FeedMin, FeedMax: Double; Cols, Rows: Integer);
var
  C, R: Integer;
  X, Y, P, F: Double;
begin
  if (Cols < 2) or (Rows < 2) or (PowerMin <= 0) or (PowerMax < PowerMin) or
     (FeedMin <= 0) or (FeedMax < FeedMin) then Exit;
  J.Clear;
  for R := 0 to Rows - 1 do
  begin
    F := FeedMin + (FeedMax - FeedMin) * R / (Rows - 1);
    for C := 0 to Cols - 1 do
    begin
      P := PowerMin + (PowerMax - PowerMin) * C / (Cols - 1);
      X := X0 + C * CellW;
      Y := Y0 + R * CellH;
      J.Add(X, Y, False, 0, 0);
      J.Add(X + CellW * 0.8, Y, True, P, F);
      J.Add(X + CellW * 0.8, Y + CellH * 0.8, True, P, F);
      J.Add(X, Y + CellH * 0.8, True, P, F);
      J.Add(X, Y, True, P, F);
    end;
  end;
end;

end.
