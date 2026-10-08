unit routerpcb_heightmap;

{ Nivelamento por sondagem (autolevel) do RouterPCB.

  Fluxo:
  1. Setup: grade Cols x Rows sobre a placa (coordenadas de saida).
  2. ProbeProgram: G-code de sondagem. No primeiro ponto, depois do G38.2,
     "G10 L20 P0 Z0" zera o Z de trabalho na superficie: as trajetorias usam
     Z = 0 ali. Percurso em serpentina (menos deslocamento).
  3. O MultiCNC executa e o GRBL responde "[PRB:x,y,z:1]" (coordenadas de
     MAQUINA) a cada G38.2. O usuario salva o log ("Save Log...") e o
     RouterPCB le com LoadProbeLog: a N-esima resposta corresponde ao N-esimo
     ponto da serpentina. Os deslocamentos X/Y entre respostas sao conferidos
     com a grade (o deslocamento de maquina se cancela).
     Tambem aceita CSV "X;Y;Z" em coordenadas de trabalho (LoadCSV).
  4. Height: altura relativa ao primeiro ponto, interpolacao bilinear na
     celula; fora da grade nao extrapola (False).
  5. Compensate: divide cada corte em trechos <= MaxSegment e soma a altura
     em cada ponto; erro se sair da grade ou se a correcao passar de
     MaxCorrection. Deslocamentos rapidos e alturas seguras nao mudam (o
     emissor de G-code so passa aqui os caminhos de corte). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, StrUtils, laserpcb_geom, routerpcb_types;

const
  RP_PROBE_HEADER = '; RouterPCB -> MultiCNC (CNC Router) - sondagem';

type
  TRPHeightMap = class
  private
    FCols, FRows: Integer;
    FX0, FY0, FDX, FDY: Double;
    FZ: array of Double;
    FSet: array of Boolean;
    function Idx(I, J: Integer): Integer; inline;
  public
    procedure Clear;
    { grade sobre Area (saida) recuada Margin (negativa = para dentro) }
    procedure Setup(const Area: TLPRect; Margin: Double; Cols, Rows: Integer);
    function Ready: Boolean;          { grade definida }
    function Complete: Boolean;       { todos os pontos medidos }
    function MeasuredCount: Integer;
    function Count: Integer;
    function PointX(I: Integer): Double;
    function PointY(J: Integer): Double;
    function Measured(I, J: Integer): Boolean;
    function GetZ(I, J: Integer): Double;
    procedure SetZ(I, J: Integer; Z: Double);
    { ordem da sondagem (serpentina): K-esimo ponto -> (I, J) }
    procedure ProbeOrder(K: Integer; out I, J: Integer);
    function Bounds: TLPRect;
    { maior e menor altura relativa ao primeiro ponto }
    procedure Range(out MinH, MaxH: Double);
    function Height(X, Y: Double; out H: Double): Boolean;
    function ProbeProgram(const L: TRPLevelOptions; const M: TRPMachineOptions;
      const Title: string): TStringList;
    { devolve quantos pontos foram lidos; mensagens em Errors }
    function LoadProbeLog(Lines: TStrings; Errors: TStrings): Integer;
    function LoadCSV(Lines: TStrings; Errors: TStrings): Integer;
    function ToCSV: TStringList;
    function Compensate(const P: TRPPaths3; MaxSegment, MaxCorrection: Double): TRPPaths3;
    property Cols: Integer read FCols;
    property Rows: Integer read FRows;
  end;

{ extrai x, y, z de uma linha com "[PRB:x,y,z:1]"; False se nao houver ou
  se a sondagem falhou (":0") }
function RPParsePRB(const Line: string; out X, Y, Z: Double): Boolean;

implementation

var
  InvFS: TFormatSettings;

function F3(V: Double): string;
begin
  Result := FormatFloat('0.###', V, InvFS);
  if Result = '-0' then Result := '0';
end;

function RPParsePRB(const Line: string; out X, Y, Z: Double): Boolean;
var P, Q: Integer; S: string; Parts: TStringList;
begin
  Result := False;
  X := 0; Y := 0; Z := 0;
  P := Pos('[PRB:', Line);
  if P = 0 then Exit;
  Q := PosEx(']', Line, P);
  if Q = 0 then Exit;
  S := Copy(Line, P + 5, Q - P - 5);          { x,y,z:1 }
  P := Pos(':', S);
  if P > 0 then
  begin
    if Trim(Copy(S, P + 1, MaxInt)) <> '1' then Exit;   { sem contato }
    S := Copy(S, 1, P - 1);
  end;
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ',';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := S;
    if Parts.Count < 3 then Exit;
    Result := TryStrToFloat(Trim(Parts[0]), X, InvFS) and TryStrToFloat(Trim(Parts[1]), Y, InvFS) and
      TryStrToFloat(Trim(Parts[2]), Z, InvFS);
  finally
    Parts.Free;
  end;
end;

{ ---------------- TRPHeightMap ---------------- }

function TRPHeightMap.Idx(I, J: Integer): Integer;
begin
  Result := J * FCols + I;
end;

procedure TRPHeightMap.Clear;
begin
  FCols := 0; FRows := 0;
  FZ := nil; FSet := nil;
end;

procedure TRPHeightMap.Setup(const Area: TLPRect; Margin: Double; Cols, Rows: Integer);
var W, H: Double; K: Integer;
begin
  Clear;
  if not Area.Valid then raise Exception.Create('Grade de sondagem sem placa');
  if (Cols < 2) or (Rows < 2) or (Cols > 50) or (Rows > 50) then
    raise Exception.Create('Grade de sondagem: de 2x2 a 50x50 pontos');
  W := LPRectWidth(Area) + 2 * Margin;
  H := LPRectHeight(Area) + 2 * Margin;
  if (W <= 0) or (H <= 0) then raise Exception.Create('Margem da sondagem maior que a placa');
  FCols := Cols; FRows := Rows;
  FX0 := Area.MinX - Margin; FY0 := Area.MinY - Margin;
  FDX := W / (Cols - 1); FDY := H / (Rows - 1);
  SetLength(FZ, Cols * Rows);
  SetLength(FSet, Cols * Rows);
  for K := 0 to High(FZ) do begin FZ[K] := 0; FSet[K] := False; end;
end;

function TRPHeightMap.Ready: Boolean;
begin
  Result := FCols >= 2;
end;

function TRPHeightMap.Count: Integer;
begin
  Result := FCols * FRows;
end;

function TRPHeightMap.MeasuredCount: Integer;
var K: Integer;
begin
  Result := 0;
  for K := 0 to High(FSet) do if FSet[K] then Inc(Result);
end;

function TRPHeightMap.Complete: Boolean;
begin
  Result := Ready and (MeasuredCount = Count);
end;

function TRPHeightMap.PointX(I: Integer): Double;
begin
  Result := FX0 + I * FDX;
end;

function TRPHeightMap.PointY(J: Integer): Double;
begin
  Result := FY0 + J * FDY;
end;

function TRPHeightMap.Measured(I, J: Integer): Boolean;
begin
  Result := FSet[Idx(I, J)];
end;

function TRPHeightMap.GetZ(I, J: Integer): Double;
begin
  Result := FZ[Idx(I, J)];
end;

procedure TRPHeightMap.SetZ(I, J: Integer; Z: Double);
begin
  FZ[Idx(I, J)] := Z;
  FSet[Idx(I, J)] := True;
end;

procedure TRPHeightMap.ProbeOrder(K: Integer; out I, J: Integer);
begin
  J := K div FCols;
  I := K mod FCols;
  if Odd(J) then I := FCols - 1 - I;
end;

function TRPHeightMap.Bounds: TLPRect;
begin
  Result := LPEmptyRect;
  if not Ready then Exit;
  LPRectInclude(Result, FX0, FY0);
  LPRectInclude(Result, PointX(FCols - 1), PointY(FRows - 1));
end;

procedure TRPHeightMap.Range(out MinH, MaxH: Double);
var K: Integer; H: Double;
begin
  MinH := 0; MaxH := 0;
  if not Complete then Exit;
  for K := 0 to High(FZ) do
  begin
    H := FZ[K] - FZ[0];
    MinH := Min(MinH, H); MaxH := Max(MaxH, H);
  end;
end;

function TRPHeightMap.Height(X, Y: Double; out H: Double): Boolean;
var FX, FY, TX, TY: Double; I, J: Integer;
begin
  H := 0;
  Result := False;
  if not Complete then Exit;
  FX := (X - FX0) / FDX;
  FY := (Y - FY0) / FDY;
  if (FX < -1e-6) or (FY < -1e-6) or (FX > FCols - 1 + 1e-6) or (FY > FRows - 1 + 1e-6) then Exit;
  I := EnsureRange(Floor(FX), 0, FCols - 2);
  J := EnsureRange(Floor(FY), 0, FRows - 2);
  TX := EnsureRange(FX - I, 0, 1);
  TY := EnsureRange(FY - J, 0, 1);
  H := (1 - TX) * (1 - TY) * FZ[Idx(I, J)] + TX * (1 - TY) * FZ[Idx(I + 1, J)] +
    (1 - TX) * TY * FZ[Idx(I, J + 1)] + TX * TY * FZ[Idx(I + 1, J + 1)] - FZ[0];
  Result := True;
end;

function TRPHeightMap.ProbeProgram(const L: TRPLevelOptions; const M: TRPMachineOptions;
  const Title: string): TStringList;
var K, I, J: Integer;
begin
  if not Ready then raise Exception.Create('Defina a grade de sondagem');
  Result := TStringList.Create;
  try
    Result.Add(RP_PROBE_HEADER);
    Result.Add('; LaserPCB -> MultiCNC (CNC Router)');
    Result.Add('; ' + Title);
    Result.Add(Format('; Grade %d x %d, %d pontos. Spindle DESLIGADO.', [FCols, FRows, Count]));
    Result.Add('; Prenda a garra na fresa e o fio na placa (cobre). Zere X/Y no canto da placa');
    Result.Add('; e deixe a fresa poucos mm acima do cobre: o 1o ponto zera o Z (G10 L20).');
    Result.Add('; Depois salve o log do MultiCNC (Save Log...) e importe no RouterPCB.');
    Result.Add('G21');
    Result.Add('G90');
    Result.Add('G94');
    Result.Add('M5');
    for K := 0 to Count - 1 do
    begin
      ProbeOrder(K, I, J);
      if K = 0 then
      begin
        { a partir da altura atual (sem Z conhecido): so desce sondando }
        Result.Add('G0 X' + F3(PointX(I)) + ' Y' + F3(PointY(J)));
        Result.Add('G38.2 Z' + F3(L.ProbeDepth) + ' F' + F3(L.ProbeFeed));
        Result.Add('G10 L20 P0 Z0');
        Result.Add('G0 Z' + F3(M.TravelZ));
      end
      else
      begin
        Result.Add('G0 X' + F3(PointX(I)) + ' Y' + F3(PointY(J)));
        Result.Add('G38.2 Z' + F3(L.ProbeDepth) + ' F' + F3(L.ProbeFeed));
        Result.Add('G0 Z' + F3(M.TravelZ));
      end;
    end;
    Result.Add('G0 Z' + F3(M.SafeZ));
    Result.Add('G0 X0 Y0');
    Result.Add('M2');
  except
    Result.Free;
    raise;
  end;
end;

function TRPHeightMap.LoadProbeLog(Lines: TStrings; Errors: TStrings): Integer;
var K, N, I, J, I0, J0: Integer; X, Y, Z, X0, Y0: Double;
  PX, PY, PZ: array of Double;
begin
  Result := 0;
  if not Ready then raise Exception.Create('Defina a grade de sondagem antes de importar');
  PX := nil; PY := nil; PZ := nil;
  for K := 0 to Lines.Count - 1 do
    if RPParsePRB(Lines[K], X, Y, Z) then
    begin
      N := Length(PX);
      SetLength(PX, N + 1); SetLength(PY, N + 1); SetLength(PZ, N + 1);
      PX[N] := X; PY[N] := Y; PZ[N] := Z;
    end;
  N := Length(PX);
  if N = 0 then
  begin
    Errors.Add('Nenhuma linha [PRB:...] no arquivo (sondagem nao executada ou log sem respostas)');
    Exit;
  end;
  { se houver mais respostas que pontos (sondagem repetida), usa as ultimas }
  if N > Count then
  begin
    Errors.Add(Format('Log com %d sondagens para %d pontos: usando as %d ultimas', [N, Count, Count]));
    PX := Copy(PX, N - Count, Count); PY := Copy(PY, N - Count, Count); PZ := Copy(PZ, N - Count, Count);
    N := Count;
  end;
  ProbeOrder(0, I0, J0);
  X0 := PX[0]; Y0 := PY[0];
  for K := 0 to N - 1 do
  begin
    ProbeOrder(K, I, J);
    if (Abs((PX[K] - X0) - (PointX(I) - PointX(I0))) > 0.25) or
      (Abs((PY[K] - Y0) - (PointY(J) - PointY(J0))) > 0.25) then
    begin
      Errors.Add(Format('Sondagem %d em X %.2f Y %.2f nao corresponde a grade: gere de novo a sondagem com a grade atual',
        [K + 1, PX[K] - X0, PY[K] - Y0], InvFS));
      Exit;
    end;
  end;
  for K := 0 to N - 1 do
  begin
    ProbeOrder(K, I, J);
    SetZ(I, J, PZ[K]);
  end;
  Result := N;
  if N < Count then
    Errors.Add(Format('Faltam %d pontos da grade (%d de %d medidos)', [Count - N, N, Count]));
end;

function TRPHeightMap.LoadCSV(Lines: TStrings; Errors: TStrings): Integer;
var K, I, J: Integer; S: string; Parts: TStringList; X, Y, Z: Double;
begin
  Result := 0;
  if not Ready then raise Exception.Create('Defina a grade de sondagem antes de importar');
  Parts := TStringList.Create;
  try
    Parts.StrictDelimiter := True;
    for K := 0 to Lines.Count - 1 do
    begin
      S := Trim(Lines[K]);
      if (S = '') or (S[1] = ';') or (S[1] = '#') then Continue;
      if Pos(';', S) > 0 then Parts.Delimiter := ';' else Parts.Delimiter := ',';
      Parts.DelimitedText := S;
      if Parts.Count < 3 then Continue;
      if not (TryStrToFloat(Trim(Parts[0]), X, InvFS) and TryStrToFloat(Trim(Parts[1]), Y, InvFS) and
        TryStrToFloat(Trim(Parts[2]), Z, InvFS)) then Continue;   { cabecalho }
      I := Round((X - FX0) / FDX); J := Round((Y - FY0) / FDY);
      if (I < 0) or (J < 0) or (I >= FCols) or (J >= FRows) or
        (Abs(PointX(I) - X) > 0.25) or (Abs(PointY(J) - Y) > 0.25) then
      begin
        Errors.Add(Format('Ponto X %.2f Y %.2f fora da grade', [X, Y], InvFS));
        Continue;
      end;
      SetZ(I, J, Z);
      Inc(Result);
    end;
  finally
    Parts.Free;
  end;
  if not Complete then
    Errors.Add(Format('Faltam %d pontos da grade', [Count - MeasuredCount]));
end;

function TRPHeightMap.ToCSV: TStringList;
var I, J: Integer;
begin
  Result := TStringList.Create;
  Result.Add('X;Y;Z');
  for J := 0 to FRows - 1 do
    for I := 0 to FCols - 1 do
      if Measured(I, J) then
        Result.Add(F3(PointX(I)) + ';' + F3(PointY(J)) + ';' + FormatFloat('0.0000', GetZ(I, J), InvFS));
end;

function TRPHeightMap.Compensate(const P: TRPPaths3; MaxSegment, MaxCorrection: Double): TRPPaths3;
var K, I, N, S: Integer; A, B: TRPPoint3; L, T, X, Y, Z, H: Double; Q: TRPPath3;

  procedure Put(PX, PY, PZ: Double);
  begin
    if not Height(PX, PY, H) then
      raise Exception.Create(Format('Corte em X %.2f Y %.2f fora da grade de sondagem: aumente a grade',
        [PX, PY], InvFS));
    if Abs(H) > MaxCorrection then
      raise Exception.Create(Format('Correcao de %.3f mm em X %.2f Y %.2f passa do limite de %.3f mm',
        [H, PX, PY, MaxCorrection], InvFS));
    RPAddPoint3(Q, PX, PY, PZ + H);
  end;

begin
  Result := nil;
  if not Complete then raise Exception.Create('Mapa de alturas incompleto');
  if (MaxSegment <= 0) or not RPFinite(MaxSegment) then raise Exception.Create('Segmento maximo invalido');
  for K := 0 to High(P) do
  begin
    Q := nil;
    if Length(P[K]) = 0 then Continue;
    Put(P[K][0].X, P[K][0].Y, P[K][0].Z);
    for I := 1 to High(P[K]) do
    begin
      A := P[K][I-1]; B := P[K][I];
      L := Hypot(B.X - A.X, B.Y - A.Y);
      N := Max(1, Ceil(L / MaxSegment - 1e-9));
      for S := 1 to N do
      begin
        T := S / N;
        X := A.X + (B.X - A.X) * T; Y := A.Y + (B.Y - A.Y) * T; Z := A.Z + (B.Z - A.Z) * T;
        Put(X, Y, Z);
      end;
    end;
    RPAddPath3(Result, Q);
  end;
end;

initialization
  InvFS := DefaultFormatSettings;
  InvFS.DecimalSeparator := '.';
end.
