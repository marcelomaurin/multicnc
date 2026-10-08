unit routerpcb_types;

{ Tipos e parametros do RouterPCB (fresagem de PCB na CNC Router).

  Unidades: mm, mm/min, RPM, segundos. Profundidades de corte sao negativas
  (Z = 0 na superficie do cobre). Cada grupo de parametros tem um padrao
  (RPDefault...) e uma validacao (RPValidate...) que so acrescenta mensagens
  em Errors e devolve False se houver problema; nenhuma validacao levanta
  excecao, para a interface poder listar todos os erros de uma vez.

  TRPPath3 e o caminho de corte ja em 3D (X, Y, Z), em coordenadas de saida:
  e o que o emissor de G-code percorre com G1 e o que o nivelamento corrige. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, laserpcb_geom;

type
  TRPSide = (rsTop, rsBottom);
  TRPToolKind = (tkVBit, tkEndMill);
  { sentido de corte com spindle horario (M3): concordante deixa o material
    que fica (cobre, placa) a direita do movimento }
  TRPCutDir = (cdClimb, cdConventional);
  TRPToolChange = (rtcPause, rtcNone);
  TRPDoubles = array of Double;
  TRPInts = array of Integer;

  TRPPoint3 = record
    X, Y, Z: Double;
  end;
  TRPPath3 = array of TRPPoint3;
  TRPPaths3 = array of TRPPath3;

  TRPMachineOptions = record
    SafeZ: Double;         { inicio, fim e troca de ferramenta (mm, > 0) }
    TravelZ: Double;       { entre cortes (mm, > 0) }
    SpinUpSeconds: Double; { espera apos ligar o spindle }
    RapidFeed: Double;     { so para estimar o tempo (mm/min) }
    ToolChange: TRPToolChange;  { arquivo unico: pausa M0 na troca }
    OneFilePerTool: Boolean;    { furacao: um arquivo por broca }
  end;

  TRPIsolationOptions = record
    Enabled: Boolean;
    Kind: TRPToolKind;
    TipWidth: Double;      { fresa V: largura da ponta (mm) }
    Angle: Double;         { fresa V: angulo incluido (graus) }
    Diameter: Double;      { fresa de topo (mm) }
    Depth: Double;         { negativa (mm) }
    Feed, PlungeFeed, RPM: Double;
    Passes: Integer;
    Overlap: Double;       { 0..0.9 }
    Direction: TRPCutDir;
  end;

  TRPDrillOptions = record
    Enabled: Boolean;
    Bits: TRPDoubles;      { brocas disponiveis (mm) }
    Tolerance: Double;     { diferenca aceita entre furo e broca (mm) }
    Depth: Double;         { negativa (mm) }
    Peck: Double;          { 0 = direto }
    PlungeFeed, SlotFeed, RPM: Double;
    MillLarge: Boolean;    { furo maior que a maior broca: fresar em circulo }
    IncludePlated, IncludeNonPlated: Boolean;
  end;

  TRPCutoutOptions = record
    Enabled: Boolean;
    ToolDiameter: Double;  { fresa de topo (mm) }
    Thickness: Double;     { espessura da placa (mm) }
    ExtraDepth: Double;    { passa da espessura (mm, >= 0) }
    StepDown: Double;      { profundidade por passada (mm, > 0) }
    Feed, PlungeFeed, RPM: Double;
    Tabs: Integer;         { pontes por contorno externo (0 = sem) }
    TabWidth: Double;      { largura da ponte que fica (mm) }
    TabHeight: Double;     { altura da ponte a partir do fundo (mm) }
    Direction: TRPCutDir;
  end;

  TRPLevelOptions = record
    Enabled: Boolean;
    Cols, Rows: Integer;
    Margin: Double;        { alem da placa (mm); pode ser negativa }
    ProbeDepth: Double;    { limite da sondagem, negativo (mm) }
    ProbeFeed: Double;
    MaxSegment: Double;    { subdivisao dos cortes (mm) }
    MaxCorrection: Double; { maior correcao aceita (mm) }
    ApplyDrill, ApplyCutout: Boolean;
  end;

function RPPoint3(X, Y, Z: Double): TRPPoint3; inline;
procedure RPAddPoint3(var P: TRPPath3; X, Y, Z: Double);
procedure RPAddPath3(var Paths: TRPPaths3; const P: TRPPath3);
function RPPath3Length(const P: TRPPath3): Double;
{ caminho 2D -> 3D numa altura fixa }
function RPLift(const P: TLPPath; Z: Double): TRPPath3;

{ largura do corte de uma fresa em V na profundidade Depth (negativa ou positiva) }
function RPVBitWidth(TipWidth, AngleDeg, Depth: Double): Double;
function RPIsolationWidth(const O: TRPIsolationOptions): Double;

function RPDefaultMachine: TRPMachineOptions;
function RPDefaultIsolation: TRPIsolationOptions;
function RPDefaultDrilling: TRPDrillOptions;
function RPDefaultCutout: TRPCutoutOptions;
function RPDefaultLevel: TRPLevelOptions;

function RPValidateMachine(const O: TRPMachineOptions; Errors: TStrings): Boolean;
function RPValidateIsolation(const O: TRPIsolationOptions; Errors: TStrings): Boolean;
function RPValidateDrilling(const O: TRPDrillOptions; Errors: TStrings): Boolean;
function RPValidateCutout(const O: TRPCutoutOptions; Errors: TStrings): Boolean;
function RPValidateLevel(const O: TRPLevelOptions; Errors: TStrings): Boolean;

{ "0.6; 0.8; 1" -> brocas em ordem crescente, sem repetidas; False se invalido }
function RPParseBits(const S: string; out Bits: TRPDoubles): Boolean;
function RPBitsToText(const Bits: array of Double): string;

function RPFinite(V: Double): Boolean; inline;

implementation

var
  InvFS: TFormatSettings;

function RPFinite(V: Double): Boolean;
begin
  Result := not (IsNan(V) or IsInfinite(V));
end;

function RPPoint3(X, Y, Z: Double): TRPPoint3;
begin
  Result.X := X; Result.Y := Y; Result.Z := Z;
end;

procedure RPAddPoint3(var P: TRPPath3; X, Y, Z: Double);
var N: Integer;
begin
  N := Length(P);
  SetLength(P, N + 1);
  P[N] := RPPoint3(X, Y, Z);
end;

procedure RPAddPath3(var Paths: TRPPaths3; const P: TRPPath3);
var N: Integer;
begin
  if Length(P) < 2 then Exit;
  N := Length(Paths);
  SetLength(Paths, N + 1);
  Paths[N] := P;
end;

function RPPath3Length(const P: TRPPath3): Double;
var I: Integer;
begin
  Result := 0;
  for I := 1 to High(P) do
    Result := Result + Sqrt(Sqr(P[I].X - P[I-1].X) + Sqr(P[I].Y - P[I-1].Y) + Sqr(P[I].Z - P[I-1].Z));
end;

function RPLift(const P: TLPPath; Z: Double): TRPPath3;
var I: Integer;
begin
  SetLength(Result, Length(P));
  for I := 0 to High(P) do Result[I] := RPPoint3(P[I].X, P[I].Y, Z);
end;

function RPVBitWidth(TipWidth, AngleDeg, Depth: Double): Double;
begin
  Result := TipWidth + 2 * Abs(Depth) * Tan(DegToRad(AngleDeg) / 2);
end;

function RPIsolationWidth(const O: TRPIsolationOptions): Double;
begin
  if O.Kind = tkVBit then Result := RPVBitWidth(O.TipWidth, O.Angle, O.Depth)
  else Result := O.Diameter;
end;

{ ---------------- padroes ---------------- }

function RPDefaultMachine: TRPMachineOptions;
begin
  Result.SafeZ := 5;
  Result.TravelZ := 2;
  Result.SpinUpSeconds := 2;
  Result.RapidFeed := 1500;
  Result.ToolChange := rtcPause;
  Result.OneFilePerTool := True;
end;

function RPDefaultIsolation: TRPIsolationOptions;
begin
  Result.Enabled := True;
  Result.Kind := tkVBit;
  Result.TipWidth := 0.1;
  Result.Angle := 30;
  Result.Diameter := 0.8;
  Result.Depth := -0.08;
  Result.Feed := 150;
  Result.PlungeFeed := 50;
  Result.RPM := 12000;
  Result.Passes := 2;
  Result.Overlap := 0.3;
  Result.Direction := cdClimb;
end;

function RPDefaultDrilling: TRPDrillOptions;
begin
  Result.Enabled := True;
  Result.Bits := nil;
  SetLength(Result.Bits, 7);
  Result.Bits[0] := 0.6; Result.Bits[1] := 0.8; Result.Bits[2] := 1.0;
  Result.Bits[3] := 1.2; Result.Bits[4] := 1.5; Result.Bits[5] := 2.0;
  Result.Bits[6] := 3.0;
  Result.Tolerance := 0.1;
  Result.Depth := -1.8;
  Result.Peck := 0;
  Result.PlungeFeed := 60;
  Result.SlotFeed := 100;
  Result.RPM := 12000;
  Result.MillLarge := True;
  Result.IncludePlated := True;
  Result.IncludeNonPlated := True;
end;

function RPDefaultCutout: TRPCutoutOptions;
begin
  Result.Enabled := True;
  Result.ToolDiameter := 2.0;
  Result.Thickness := 1.6;
  Result.ExtraDepth := 0.1;
  Result.StepDown := 0.6;
  Result.Feed := 200;
  Result.PlungeFeed := 60;
  Result.RPM := 12000;
  Result.Tabs := 4;
  Result.TabWidth := 3;
  Result.TabHeight := 0.6;
  Result.Direction := cdConventional;
end;

function RPDefaultLevel: TRPLevelOptions;
begin
  Result.Enabled := False;
  Result.Cols := 5;
  Result.Rows := 4;
  Result.Margin := -2;   { pontos 2 mm para dentro da borda (sobre o cobre) }
  Result.ProbeDepth := -2;
  Result.ProbeFeed := 50;
  Result.MaxSegment := 1;
  Result.MaxCorrection := 0.5;
  Result.ApplyDrill := False;
  Result.ApplyCutout := False;
end;

{ ---------------- validacao ---------------- }

function Bad(Errors: TStrings; const Msg: string): Boolean;
begin
  if Errors <> nil then Errors.Add(Msg);
  Result := False;
end;

function InRange(V, Lo, Hi: Double): Boolean;
begin
  Result := RPFinite(V) and (V >= Lo) and (V <= Hi);
end;

function RPValidateMachine(const O: TRPMachineOptions; Errors: TStrings): Boolean;
begin
  Result := True;
  if not InRange(O.SafeZ, 0.5, 100) then Result := Bad(Errors, 'Maquina: Z seguro deve ficar entre 0,5 e 100 mm');
  if not InRange(O.TravelZ, 0.2, 100) then Result := Bad(Errors, 'Maquina: Z entre cortes deve ficar entre 0,2 e 100 mm');
  if RPFinite(O.SafeZ) and RPFinite(O.TravelZ) and (O.TravelZ > O.SafeZ) then
    Result := Bad(Errors, 'Maquina: Z entre cortes maior que o Z seguro');
  if not InRange(O.SpinUpSeconds, 0, 60) then Result := Bad(Errors, 'Maquina: espera do spindle entre 0 e 60 s');
  if not InRange(O.RapidFeed, 1, 100000) then Result := Bad(Errors, 'Maquina: velocidade de deslocamento invalida');
end;

function RPValidateIsolation(const O: TRPIsolationOptions; Errors: TStrings): Boolean;
begin
  Result := True;
  if not O.Enabled then Exit;
  if O.Kind = tkVBit then
  begin
    if not InRange(O.TipWidth, 0.01, 2) then Result := Bad(Errors, 'Isolacao: ponta da fresa V entre 0,01 e 2 mm');
    if not InRange(O.Angle, 5, 120) then Result := Bad(Errors, 'Isolacao: angulo da fresa V entre 5 e 120 graus');
  end
  else if not InRange(O.Diameter, 0.05, 6) then Result := Bad(Errors, 'Isolacao: diametro da fresa entre 0,05 e 6 mm');
  if not InRange(O.Depth, -1, -0.005) then Result := Bad(Errors, 'Isolacao: profundidade negativa, entre -0,005 e -1 mm');
  if not InRange(O.Feed, 1, 10000) then Result := Bad(Errors, 'Isolacao: avanco invalido');
  if not InRange(O.PlungeFeed, 1, 5000) then Result := Bad(Errors, 'Isolacao: avanco de mergulho invalido');
  if not InRange(O.RPM, 0, 60000) then Result := Bad(Errors, 'Isolacao: rotacao invalida');
  if (O.Passes < 1) or (O.Passes > 50) then Result := Bad(Errors, 'Isolacao: passadas entre 1 e 50');
  if not InRange(O.Overlap, 0, 0.9) then Result := Bad(Errors, 'Isolacao: sobreposicao entre 0 e 90%');
end;

function RPValidateDrilling(const O: TRPDrillOptions; Errors: TStrings): Boolean;
var I: Integer;
begin
  Result := True;
  if not O.Enabled then Exit;
  if Length(O.Bits) = 0 then Result := Bad(Errors, 'Furacao: informe pelo menos uma broca');
  for I := 0 to High(O.Bits) do
    if not InRange(O.Bits[I], 0.1, 10) then
    begin
      Result := Bad(Errors, 'Furacao: broca fora de 0,1..10 mm');
      Break;
    end;
  if not InRange(O.Tolerance, 0, 1) then Result := Bad(Errors, 'Furacao: tolerancia entre 0 e 1 mm');
  if not InRange(O.Depth, -10, -0.1) then Result := Bad(Errors, 'Furacao: profundidade negativa, entre -0,1 e -10 mm');
  if not InRange(O.Peck, 0, 10) then Result := Bad(Errors, 'Furacao: bicada entre 0 e 10 mm');
  if not InRange(O.PlungeFeed, 1, 5000) then Result := Bad(Errors, 'Furacao: avanco de mergulho invalido');
  if not InRange(O.SlotFeed, 1, 5000) then Result := Bad(Errors, 'Furacao: avanco nos rasgos invalido');
  if not InRange(O.RPM, 0, 60000) then Result := Bad(Errors, 'Furacao: rotacao invalida');
  if not (O.IncludePlated or O.IncludeNonPlated) then Result := Bad(Errors, 'Furacao: escolha PTH, NPTH ou ambos');
end;

function RPValidateCutout(const O: TRPCutoutOptions; Errors: TStrings): Boolean;
begin
  Result := True;
  if not O.Enabled then Exit;
  if not InRange(O.ToolDiameter, 0.3, 6.35) then Result := Bad(Errors, 'Recorte: fresa entre 0,3 e 6,35 mm');
  if not InRange(O.Thickness, 0.2, 5) then Result := Bad(Errors, 'Recorte: espessura da placa entre 0,2 e 5 mm');
  if not InRange(O.ExtraDepth, 0, 2) then Result := Bad(Errors, 'Recorte: profundidade extra entre 0 e 2 mm');
  if not InRange(O.StepDown, 0.05, 5) then Result := Bad(Errors, 'Recorte: passo de profundidade entre 0,05 e 5 mm');
  if not InRange(O.Feed, 1, 10000) then Result := Bad(Errors, 'Recorte: avanco invalido');
  if not InRange(O.PlungeFeed, 1, 5000) then Result := Bad(Errors, 'Recorte: avanco de mergulho invalido');
  if not InRange(O.RPM, 0, 60000) then Result := Bad(Errors, 'Recorte: rotacao invalida');
  if (O.Tabs < 0) or (O.Tabs > 20) then Result := Bad(Errors, 'Recorte: pontes entre 0 e 20');
  if O.Tabs > 0 then
  begin
    if not InRange(O.TabWidth, 0.3, 20) then Result := Bad(Errors, 'Recorte: largura da ponte entre 0,3 e 20 mm');
    if not InRange(O.TabHeight, 0.1, 5) then Result := Bad(Errors, 'Recorte: altura da ponte entre 0,1 e 5 mm')
    else if RPFinite(O.Thickness) and (O.TabHeight >= O.Thickness) then
      Result := Bad(Errors, 'Recorte: ponte mais alta que a placa');
  end;
end;

function RPValidateLevel(const O: TRPLevelOptions; Errors: TStrings): Boolean;
begin
  Result := True;
  if not O.Enabled then Exit;
  if (O.Cols < 2) or (O.Cols > 50) or (O.Rows < 2) or (O.Rows > 50) then
    Result := Bad(Errors, 'Nivelamento: grade de 2x2 a 50x50 pontos');
  if not InRange(O.Margin, -50, 50) then Result := Bad(Errors, 'Nivelamento: margem entre -50 e 50 mm');
  if not InRange(O.ProbeDepth, -20, -0.1) then Result := Bad(Errors, 'Nivelamento: limite da sondagem negativo, entre -0,1 e -20 mm');
  if not InRange(O.ProbeFeed, 1, 1000) then Result := Bad(Errors, 'Nivelamento: avanco da sondagem entre 1 e 1000 mm/min');
  if not InRange(O.MaxSegment, 0.1, 20) then Result := Bad(Errors, 'Nivelamento: segmento maximo entre 0,1 e 20 mm');
  if not InRange(O.MaxCorrection, 0.01, 5) then Result := Bad(Errors, 'Nivelamento: correcao maxima entre 0,01 e 5 mm');
end;

{ ---------------- brocas ---------------- }

function RPParseBits(const S: string; out Bits: TRPDoubles): Boolean;
var Parts: TStringList; I, J, N: Integer; V, T: Double; Txt: string;
begin
  Bits := nil;
  Result := False;
  Txt := StringReplace(S, ',', '.', [rfReplaceAll]);   { aceita 0,8 }
  Txt := StringReplace(Txt, ' ', ';', [rfReplaceAll]);
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ';';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := Txt;
    N := 0;
    for I := 0 to Parts.Count - 1 do
    begin
      if Trim(Parts[I]) = '' then Continue;
      if not TryStrToFloat(Trim(Parts[I]), V, InvFS) or not RPFinite(V) or (V <= 0) then Exit;
      J := 0;
      while (J < N) and (Abs(Bits[J] - V) > 1e-9) do Inc(J);
      if J < N then Continue;
      SetLength(Bits, N + 1);
      Bits[N] := V;
      Inc(N);
    end;
    { ordem crescente }
    for I := 1 to N - 1 do
    begin
      T := Bits[I];
      J := I - 1;
      while (J >= 0) and (Bits[J] > T) do
      begin
        Bits[J + 1] := Bits[J];
        Dec(J);
      end;
      Bits[J + 1] := T;
    end;
    Result := N > 0;
  finally
    Parts.Free;
  end;
end;

function RPBitsToText(const Bits: array of Double): string;
var I: Integer;
begin
  Result := '';
  for I := 0 to High(Bits) do
  begin
    if I > 0 then Result := Result + '; ';
    Result := Result + FormatFloat('0.0##', Bits[I], InvFS);
  end;
end;

initialization
  InvFS := DefaultFormatSettings;
  InvFS.DecimalSeparator := '.';
  InvFS.ThousandSeparator := #0;
end.
