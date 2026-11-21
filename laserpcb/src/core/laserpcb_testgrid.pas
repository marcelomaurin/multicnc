unit laserpcb_testgrid;
{$mode objfpc}{$H+}
{ Gabarito de teste de material (aferição) do LaserPCB.

  Numa placa pequena (padrao 100 x 50 mm) grava uma grade: linhas = potencia
  (%), colunas = numero de passadas, todas na mesma velocidade (padrao
  1 mm/s). Cada celula e um quadrado: se o miolo solta, a combinacao cortou;
  se ficou so o sulco, fez trilha. Os rotulos (potencia, passadas, W do
  laser e velocidade) sao gravados antes, com potencia baixa, para o
  gabarito ficar escrito.

  Ordem de execucao: textos; depois as celulas da menor para a maior
  energia, para as pecas que soltam nao mexerem nas seguintes. }
interface
uses SysUtils, Math, makepcb_model, makepcb_font, laserpcb_job, laserpcb_types;
type
  TLPTestGrid = record
    PlateW, PlateH: Double;        { placa de teste, mm }
    OriginX, OriginY: Double;      { canto inferior esquerdo na mesa }
    Feed: Double;                  { mm/min das celulas }
    Powers: array of Double;       { % por linha (de baixo para cima) }
    Passes: array of Integer;      { passadas por coluna }
    TextPercent, TextFeed: Double; { gravacao dos rotulos }
    OpticalW, SMax: Double;
    BedW, BedH: Double;
  end;
  TLPCellRect = record
    X0, Y0, X1, Y1: Double;        { coordenadas na placa }
  end;

function LPDefaultTestGrid: TLPTestGrid;
function LPParseNumbers(const S: string; out Values: array of Double; MaxCount: Integer): Integer;
procedure LPValidateTestGrid(const G: TLPTestGrid);
function LPTestCell(const G: TLPTestGrid; Row, Col: Integer): TLPCellRect;
{ energia nominal entregue por mm na celula (todas as passadas), J/mm }
function LPTestCellEnergy(const G: TLPTestGrid; Row, Col: Integer): Double;
{ tracos dos rotulos em coordenadas da placa (para previa e gravacao) }
function LPTestGridLabels(const G: TLPTestGrid): TMPStrokes;
function LPBuildTestGridJob(const G: TLPTestGrid): TLaserPCBJob;

implementation

const
  LABEL_W = 13;   { coluna dos rotulos de potencia }
  TOP_H = 12;     { titulo + cabecalho das passadas }
  EDGE = 3;

function LPDefaultTestGrid: TLPTestGrid;
begin
  Result := Default(TLPTestGrid);
  Result.PlateW := 100; Result.PlateH := 50;
  Result.OriginX := 5; Result.OriginY := 5;
  Result.Feed := 60;
  SetLength(Result.Powers, 4);
  Result.Powers[0] := 40; Result.Powers[1] := 60; Result.Powers[2] := 80; Result.Powers[3] := 100;
  SetLength(Result.Passes, 5);
  Result.Passes[0] := 1; Result.Passes[1] := 2; Result.Passes[2] := 4; Result.Passes[3] := 6; Result.Passes[4] := 8;
  Result.TextPercent := 20; Result.TextFeed := 600;
  Result.SMax := 1000;
end;

function LPParseNumbers(const S: string; out Values: array of Double; MaxCount: Integer): Integer;
{ "40, 60, 80, 100" ou "40;60" - decimais com ponto }
var Parts: TStringArray; I: Integer; V: Double; FS: TFormatSettings;
begin
  Result := 0;
  FS := DefaultFormatSettings; FS.DecimalSeparator := '.';
  Parts := S.Split([',', ';', ' ', #9], TStringSplitOptions.ExcludeEmpty);
  for I := 0 to High(Parts) do
  begin
    if not TryStrToFloat(Trim(Parts[I]), V, FS) then raise Exception.Create('Lista invalida: "'+Parts[I]+'"');
    if Result >= Min(MaxCount, Length(Values)) then raise Exception.Create(Format('Use no maximo %d valores.',[MaxCount]));
    Values[Result] := V; Inc(Result);
  end;
  if Result = 0 then raise Exception.Create('Lista vazia.');
end;

procedure LPValidateTestGrid(const G: TLPTestGrid);
var I: Integer; C: TLPCellRect;
begin
  if (Length(G.Powers) < 1) or (Length(G.Passes) < 1) then raise Exception.Create('Informe potencias e passadas.');
  for I := 0 to High(G.Powers) do
    if not (G.Powers[I] > 0) or (G.Powers[I] > 100) then raise Exception.Create('Potencias entre 1 e 100%.');
  for I := 0 to High(G.Passes) do
    if (G.Passes[I] < 1) or (G.Passes[I] > 100) then raise Exception.Create('Passadas entre 1 e 100.');
  if not (G.Feed >= 1) or (G.Feed > 100000) then raise Exception.Create('Velocidade invalida.');
  if not (G.TextPercent > 0) or (G.TextPercent > 100) or not (G.TextFeed >= 1) then
    raise Exception.Create('Potencia e velocidade dos textos invalidas.');
  if not (G.SMax >= 1) then raise Exception.Create('S-max invalido.');
  if not (G.PlateW >= 30) or not (G.PlateH >= 25) then raise Exception.Create('Placa de teste minima: 30 x 25 mm.');
  if (G.OriginX < 0) or (G.OriginY < 0) or ((G.BedW > 0) and (G.OriginX+G.PlateW > G.BedW)) or
    ((G.BedH > 0) and (G.OriginY+G.PlateH > G.BedH)) then
    raise Exception.Create('A placa de teste nao cabe na mesa nessa posicao.');
  C := LPTestCell(G, 0, 0);
  if Min(C.X1-C.X0, C.Y1-C.Y0) < 2 then
    raise Exception.Create('Celulas menores que 2 mm: aumente a placa ou reduza potencias/passadas.');
end;

function LPTestCell(const G: TLPTestGrid; Row, Col: Integer): TLPCellRect;
var PX, PY, Side, CX, CY: Double;
begin
  PX := (G.PlateW - LABEL_W - EDGE) / Max(1, Length(G.Passes));
  PY := (G.PlateH - TOP_H - EDGE) / Max(1, Length(G.Powers));
  Side := Min(PX, PY) * 0.6;
  CX := LABEL_W + PX*(Col+0.5);
  CY := EDGE + PY*(Row+0.5);
  Result.X0 := CX - Side/2; Result.X1 := CX + Side/2;
  Result.Y0 := CY - Side/2; Result.Y1 := CY + Side/2;
end;

function LPTestCellEnergy(const G: TLPTestGrid; Row, Col: Integer): Double;
begin
  Result := G.OpticalW * G.Powers[Row] / 100 * 60 / G.Feed * G.Passes[Col];
end;

procedure AddStrokes(var All: TMPStrokes; const S: TMPStrokes);
var I, N: Integer;
begin
  N := Length(All); SetLength(All, N + Length(S));
  for I := 0 to High(S) do All[N+I] := S[I];
end;

function LPTestGridLabels(const G: TLPTestGrid): TMPStrokes;
var I: Integer; C: TLPCellRect; S: string; H, PY: Double; FS: TFormatSettings;
begin
  Result := nil;
  FS := DefaultFormatSettings; FS.DecimalSeparator := '.';
  { titulo: W do laser e velocidade }
  if G.OpticalW > 0 then S := Format('%gW %gMM/S', [G.OpticalW, G.Feed/60], FS)
  else S := Format('%gMM/S', [G.Feed/60], FS);
  H := 2.5;
  while (MPTextWidth(S, H) > G.PlateW - 2*EDGE) and (H > 1.2) do H := H - 0.1;
  AddStrokes(Result, MPTextStrokes(S, EDGE, G.PlateH - 4, H));
  { cabecalho: passadas por coluna }
  for I := 0 to High(G.Passes) do
  begin
    C := LPTestCell(G, High(G.Powers), I);
    S := IntToStr(G.Passes[I]) + 'X';
    H := Min(2, (C.X1-C.X0)*0.5);
    AddStrokes(Result, MPTextStrokes(S, (C.X0+C.X1)/2 - MPTextWidth(S, H)/2, G.PlateH - TOP_H + 3, H));
  end;
  { potencia por linha }
  PY := (G.PlateH - TOP_H - EDGE) / Max(1, Length(G.Powers));
  for I := 0 to High(G.Powers) do
  begin
    C := LPTestCell(G, I, 0);
    S := Format('%g%%', [G.Powers[I]], FS);
    H := Min(2, PY*0.4);
    while (MPTextWidth(S, H) > LABEL_W - 2) and (H > 1) do H := H - 0.1;
    AddStrokes(Result, MPTextStrokes(S, 1.5, (C.Y0+C.Y1)/2 - H/2, H));
  end;
end;

function LPBuildTestGridJob(const G: TLPTestGrid): TLaserPCBJob;
var Labels: TMPStrokes; I, J, R, K, N, T: Integer; S: Double; C: TLPCellRect;
  Order: array of Integer; E: array of Double;
  procedure Path(const P: TMPPoints; Power, Feed: Double);
  var A: Integer;
  begin
    if Length(P) < 2 then Exit;
    Result.AddPointWithParams(G.OriginX+P[0].X, G.OriginY+P[0].Y, False, 0, 0);
    for A := 1 to High(P) do
      Result.AddPointWithParams(G.OriginX+P[A].X, G.OriginY+P[A].Y, True, Power, Feed);
  end;
  function Square(const Cell: TLPCellRect): TMPPoints;
  begin
    SetLength(Result, 5);
    Result[0] := MPPoint(Cell.X0, Cell.Y0); Result[1] := MPPoint(Cell.X1, Cell.Y0);
    Result[2] := MPPoint(Cell.X1, Cell.Y1); Result[3] := MPPoint(Cell.X0, Cell.Y1);
    Result[4] := Result[0];
  end;
begin
  LPValidateTestGrid(G);
  Result := TLaserPCBJob.Create;
  try
    Result.Profile.SMax := G.SMax; Result.Profile.Passes := 1;
    Result.Width := G.BedW; Result.Height := G.BedH;
    { 1) rotulos }
    Labels := LPTestGridLabels(G);
    S := Max(1, Round(G.SMax*G.TextPercent/100));
    for I := 0 to High(Labels) do Path(Labels[I], S, G.TextFeed);
    { 2) celulas em ordem crescente de energia (potencia x passadas) }
    N := Length(G.Powers)*Length(G.Passes);
    SetLength(Order, N); SetLength(E, N);
    for I := 0 to N-1 do
    begin
      Order[I] := I;
      E[I] := G.Powers[I div Length(G.Passes)] * G.Passes[I mod Length(G.Passes)];
    end;
    for I := 1 to N-1 do
    begin
      J := I; T := Order[I];
      while (J > 0) and (E[Order[J-1]] > E[T]) do begin Order[J] := Order[J-1]; Dec(J); end;
      Order[J] := T;
    end;
    for K := 0 to N-1 do
    begin
      R := Order[K] div Length(G.Passes); J := Order[K] mod Length(G.Passes);
      C := LPTestCell(G, R, J);
      S := Max(1, Round(G.SMax*G.Powers[R]/100));
      for I := 1 to G.Passes[J] do Path(Square(C), S, G.Feed);
    end;
  except Result.Free; raise; end;
end;

end.
