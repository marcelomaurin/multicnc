unit laserpcb_job;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Math, laserpcb_types;
type
  TLaserPCBJob = class
  private
    FPoints: array of TPathPoint;
    function MirrorAxis: Double;
  public
    Name: string;
    Width, Height: Double;
    Side: TPCBLayerSide;
    Mirror: Boolean;
    Profile: TLaserProfile;
    Warnings: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure AddPoint(X, Y: Double; OnOff: Boolean);
    procedure AddPointWithParams(X, Y: Double; OnOff: Boolean; Power, Feed: Double);
    function Count: Integer;
    function Point(I: Integer): TPathPoint;
    function RawPoint(I: Integer): TPathPoint;
    procedure ApplyBottomMirror;
  end;
implementation
constructor TLaserPCBJob.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
  Profile.Passes := 1;
  Profile.SpotMM := 0.1;
  Profile.SMax := 1000;
end;

destructor TLaserPCBJob.Destroy;
begin Warnings.Free; inherited Destroy; end;

procedure TLaserPCBJob.Clear;
begin
  SetLength(FPoints, 0);
  Width := 0; Height := 0;
  Mirror := False; Side := lsTop;
  Warnings.Clear;
end;

procedure TLaserPCBJob.AddPoint(X, Y: Double; OnOff: Boolean);
begin AddPointWithParams(X, Y, OnOff, 0, 0); end;

procedure TLaserPCBJob.AddPointWithParams(X, Y: Double; OnOff: Boolean;
  Power, Feed: Double);
var N: Integer;
begin
  if IsNan(X) or IsInfinite(X) or IsNan(Y) or IsInfinite(Y) or
     IsNan(Power) or IsInfinite(Power) or IsNan(Feed) or IsInfinite(Feed) then
    raise Exception.Create('Coordenadas e parametros devem ser numeros finitos');
  if (Power < 0) or (Feed < 0) then
    raise Exception.Create('Potencia e velocidade nao podem ser negativas');
  N := Length(FPoints); SetLength(FPoints, N + 1);
  FPoints[N].X := X; FPoints[N].Y := Y;
  FPoints[N].LaserOn := OnOff;
  FPoints[N].Power := Power; FPoints[N].Feed := Feed;
end;

function TLaserPCBJob.Count: Integer;
begin Result := Length(FPoints); end;

function TLaserPCBJob.RawPoint(I: Integer): TPathPoint;
begin
  if (I < 0) or (I >= Count) then raise ERangeError.Create('Indice de ponto invalido');
  Result := FPoints[I];
end;

function TLaserPCBJob.MirrorAxis: Double;
var I: Integer; MinX, MaxX: Double;
begin
  if Width > 0 then Exit(Width);
  if Count = 0 then Exit(0);
  MinX := FPoints[0].X; MaxX := MinX;
  for I := 1 to Count - 1 do
  begin MinX := Min(MinX, FPoints[I].X); MaxX := Max(MaxX, FPoints[I].X); end;
  Result := MinX + MaxX;
end;

function TLaserPCBJob.Point(I: Integer): TPathPoint;
begin
  Result := RawPoint(I);
  { Espelho e transformacao de leitura: exportar ou cancelar nao altera a fonte. }
  if Mirror then Result.X := MirrorAxis - Result.X;
end;

procedure TLaserPCBJob.ApplyBottomMirror;
begin
  { API historica mantida; Point aplica Mirror de maneira idempotente. }
end;
end.
