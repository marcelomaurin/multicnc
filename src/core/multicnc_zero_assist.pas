unit multicnc_zero_assist;

{ MultiCNC - zero do router pelo bloco de material.

  O operador mostra onde esta o bloco de madeira: leva a fresa ate um canto
  do bloco (etapa X/Y) e depois encosta a fresa no topo do bloco (etapa Z).
  O MultiCNC sabe onde esse canto fica nas coordenadas do G-code e calcula
  onde deve ficar o ponto zero do programa:

    zero XY = posicao marcada - canto do bloco no programa
    zero Z  = posicao ao encostar - Z do topo do bloco no programa
              (0 com o zero no topo; a espessura com o zero na mesa)

  Onde o bloco fica no programa:
  - cabecalho do contrato da suite (MakeRouter): "; MS-DATUM: XY=.." diz em
    que ponto do bloco esta o zero e "; MS-STOCK: W= H= T=" o tamanho;
  - sem cabecalho, corte todo em X/Y positivos: o zero e o canto inferior
    esquerdo do bloco ("X0 Y0 no canto", o mais comum);
  - sem cabecalho, com coordenadas negativas: o canto do bloco encosta no
    canto da area cortada (caixa dos movimentos de corte).

  Aplica com G92 (o mesmo mecanismo do "Zero Workpiece"). Sem LCL. }

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, StrUtils, multisuite_gcode_writer;

type
  { ponto do bloco que o operador marca }
  TBlockPoint = (bpBottomLeft, bpBottomRight, bpTopLeft, bpTopRight, bpCenter);

  TCutBounds = record
    Valid: Boolean;
    MinX, MinY, MaxX, MaxY, MinZ: Double;   { movimentos de corte (G1/G2/G3) }
  end;

  TBlockPlacement = record
    Valid: Boolean;
    FromHeader: Boolean;      { veio do cabecalho (MS-DATUM/MS-STOCK) }
    X0, Y0: Double;           { canto inferior esquerdo do bloco nas coordenadas do programa }
    W, H: Double;             { tamanho do bloco (mm) }
    Top: Double;              { Z do topo do bloco no programa }
    DatumTable: Boolean;      { Z0 na mesa (o topo fica na espessura do bloco) }
    MinZ: Double;             { Z mais fundo do corte no programa }
    HasCut: Boolean;
    Thickness: Double;        { espessura (0 = desconhecida) }
    Datum: string;            { descricao para o operador }
  end;

const
  { folga minima entre o fundo do corte e a face de baixo do bloco: passar da
    espessura leva a fresa na mesa e quebra a broca }
  MIN_DEPTH_CLEARANCE = 2.0;

  BLOCK_POINT_NAMES: array[TBlockPoint] of string = ('Canto inferior esquerdo',
    'Canto inferior direito', 'Canto superior esquerdo', 'Canto superior direito', 'Centro do bloco');

{ caixa dos movimentos de corte; entende G20/G21, G90/G91 e comentarios }
function CutBounds(Lines: TStrings): TCutBounds;
{ onde o bloco fica no programa (cabecalho, ou a caixa do corte) }
function BlockPlacement(Lines: TStrings): TBlockPlacement;
{ ponto do bloco nas coordenadas do programa }
procedure BlockPointInProgram(const B: TBlockPlacement; P: TBlockPoint; out PX, PY: Double);
{ onde fica o zero X/Y, nas coordenadas atuais, com o ponto do bloco marcado em (MX, MY) }
procedure ZeroXYFromBlock(MX, MY: Double; const B: TBlockPlacement; P: TBlockPoint; out ZX, ZY: Double);
{ onde fica o zero Z, nas coordenadas atuais, com a fresa encostada no topo em TouchZ }
function ZeroZFromTouch(TouchZ: Double; const B: TBlockPlacement): Double;
{ G92 que faz o ponto marcado (MX, MY) valer o ponto do bloco no programa,
  com a maquina parada em (CurX, CurY) }
function G92ForBlockXY(CurX, CurY, MX, MY: Double; const B: TBlockPlacement; P: TBlockPoint): string;
{ G92 que faz a altura marcada valer o topo do bloco, com a maquina em CurZ }
function G92ForTop(CurZ, TouchZ: Double; const B: TBlockPlacement): string;
function FmtMM(V: Double): string;
{ topo do bloco no programa para a espessura informada (Z0 na mesa: = espessura) }
function BlockTop(const B: TBlockPlacement; Thickness: Double): Double;
{ profundidade do corte (do topo ao Z mais fundo) contra a espessura menos a
  folga (no minimo MIN_DEPTH_CLEARANCE). False = o corte passa do permitido. }
function CheckCutDepth(const B: TBlockPlacement; Thickness, Clearance: Double;
  out Depth, Allowed: Double; out Msg: string): Boolean;

implementation

var
  InvFS: TFormatSettings;

function FmtMM(V: Double): string;
begin
  if Abs(V) < 0.0005 then V := 0;
  Result := FormatFloat('0.###', V, InvFS);
end;

function CutBounds(Lines: TStrings): TCutBounds;
var
  I, P, Q, Motion: Integer;
  L, Num: string;
  C: Char;
  V, X, Y, Z, NX, NY, NZ, Scale: Double;
  Absolute, HasMove, Skip: Boolean;

  procedure Add(AX, AY, AZ: Double);
  begin
    if not Result.Valid then
    begin
      Result.Valid := True;
      Result.MinX := AX; Result.MaxX := AX; Result.MinY := AY; Result.MaxY := AY; Result.MinZ := AZ;
    end
    else
    begin
      Result.MinX := Min(Result.MinX, AX); Result.MaxX := Max(Result.MaxX, AX);
      Result.MinY := Min(Result.MinY, AY); Result.MaxY := Max(Result.MaxY, AY);
      Result.MinZ := Min(Result.MinZ, AZ);
    end;
  end;

begin
  Result := Default(TCutBounds);
  X := 0; Y := 0; Z := 0;
  Motion := 0; Absolute := True; Scale := 1;
  for I := 0 to Lines.Count - 1 do
  begin
    L := UpperCase(Lines[I]);
    P := Pos(';', L);
    if P > 0 then L := Copy(L, 1, P - 1);
    while Pos('(', L) > 0 do
    begin
      P := Pos('(', L);
      Q := Pos(')', L);
      if Q < P then Q := Length(L);
      Delete(L, P, Q - P + 1);
    end;
    L := Trim(L);
    if (L = '') or (L[1] in ['%', '$']) then Continue;
    NX := X; NY := Y; NZ := Z;
    HasMove := False; Skip := False;
    P := 1;
    while P <= Length(L) do
    begin
      C := L[P];
      if not (C in ['A'..'Z']) then begin Inc(P); Continue; end;
      Q := P + 1;
      while (Q <= Length(L)) and (L[Q] in [' ', #9]) do Inc(Q);
      Num := '';
      while (Q <= Length(L)) and (L[Q] in ['0'..'9', '.', '-', '+']) do
      begin
        Num := Num + L[Q];
        Inc(Q);
      end;
      P := Q;
      if not TryStrToFloat(Num, V, InvFS) then Continue;
      case C of
        'G':
          case Round(V * 10) of
            0, 10, 20, 30: Motion := Round(V);
            200: Scale := 25.4;
            210: Scale := 1;
            900: Absolute := True;
            910: Absolute := False;
            280, 300, 530, 920, 381, 382, 383, 384: Skip := True;  { maquina/probe/G92 }
          end;
        'X': begin if Absolute then NX := V * Scale else NX := X + V * Scale; HasMove := True; end;
        'Y': begin if Absolute then NY := V * Scale else NY := Y + V * Scale; HasMove := True; end;
        'Z': begin if Absolute then NZ := V * Scale else NZ := Z + V * Scale; HasMove := True; end;
      end;
    end;
    if Skip or not HasMove then Continue;
    if Motion in [1, 2, 3] then
    begin
      Add(X, Y, Z);
      Add(NX, NY, NZ);
    end;
    X := NX; Y := NY; Z := NZ;
  end;
end;

function DatumFractions(const D: string; out FX, FY: Double): Boolean;
begin
  Result := True;
  FX := 0; FY := 0;
  if D = 'BL' then begin FX := 0; FY := 0; end
  else if D = 'BC' then begin FX := 0.5; FY := 0; end
  else if D = 'BR' then begin FX := 1; FY := 0; end
  else if D = 'ML' then begin FX := 0; FY := 0.5; end
  else if D = 'C' then begin FX := 0.5; FY := 0.5; end
  else if D = 'MR' then begin FX := 1; FY := 0.5; end
  else if D = 'TL' then begin FX := 0; FY := 1; end
  else if D = 'TC' then begin FX := 0.5; FY := 1; end
  else if D = 'TR' then begin FX := 1; FY := 1; end
  else Result := False;
end;

function DatumName(const D: string): string;
begin
  if D = 'BL' then Result := 'canto inferior esquerdo'
  else if D = 'BC' then Result := 'meio da borda de baixo'
  else if D = 'BR' then Result := 'canto inferior direito'
  else if D = 'ML' then Result := 'meio da borda esquerda'
  else if D = 'C' then Result := 'centro'
  else if D = 'MR' then Result := 'meio da borda direita'
  else if D = 'TL' then Result := 'canto superior esquerdo'
  else if D = 'TC' then Result := 'meio da borda de cima'
  else if D = 'TR' then Result := 'canto superior direito'
  else Result := D;
end;

function BlockPlacement(Lines: TStrings): TBlockPlacement;
var H: TSuiteGCodeHeader; HB: TSuiteBounds; CB: TCutBounds; FX, FY: Double;
begin
  Result := Default(TBlockPlacement);
  if SuiteParseHeader(Lines, H, HB) and (H.StockW > 0) and (H.StockH > 0) and
    DatumFractions(UpperCase(H.DatumXY), FX, FY) then
  begin
    Result.Valid := True;
    Result.FromHeader := True;
    Result.W := H.StockW; Result.H := H.StockH;
    Result.X0 := -FX * H.StockW;
    Result.Y0 := -FY * H.StockH;
    Result.Thickness := H.StockT;
    Result.DatumTable := SameText(H.DatumZ, 'TABLE');
    if Result.DatumTable and (H.StockT > 0) then Result.Top := H.StockT else Result.Top := 0;
    CB := CutBounds(Lines);
    Result.HasCut := CB.Valid;
    Result.MinZ := CB.MinZ;
    Result.Datum := Format('Bloco de %s x %s x %s mm do cabecalho; zero X/Y no %s do bloco, Z0 %s',
      [FmtMM(H.StockW), FmtMM(H.StockH), FmtMM(H.StockT), DatumName(UpperCase(H.DatumXY)),
       IfThen(Result.Top > 0, 'na mesa (topo do bloco em Z ' + FmtMM(Result.Top) + ')', 'no topo do bloco')]);
    Exit;
  end;
  CB := CutBounds(Lines);
  if not CB.Valid then Exit;
  Result.Valid := True;
  Result.HasCut := True;
  Result.MinZ := CB.MinZ;
  Result.Top := 0;
  if (CB.MinX >= -1E-6) and (CB.MinY >= -1E-6) then
  begin
    { corte todo no quadrante positivo: o zero e o canto inferior esquerdo do
      bloco (convencao mais comum: "X0 Y0 no canto") }
    Result.X0 := 0; Result.Y0 := 0;
    Result.W := CB.MaxX; Result.H := CB.MaxY;
    Result.Datum := Format('Sem dados do bloco no G-code: o corte fica todo em X/Y positivos, entao o zero X/Y ' +
      'e o canto inferior esquerdo do bloco (corte de X %s a %s, Y %s a %s); Z0 no topo do bloco',
      [FmtMM(CB.MinX), FmtMM(CB.MaxX), FmtMM(CB.MinY), FmtMM(CB.MaxY)]);
  end
  else
  begin
    { coordenadas negativas (zero no meio da peca): o canto do bloco encosta
      no canto da area cortada }
    Result.X0 := CB.MinX; Result.Y0 := CB.MinY;
    Result.W := CB.MaxX - CB.MinX; Result.H := CB.MaxY - CB.MinY;
    Result.Datum := Format('Sem dados do bloco no G-code e corte com coordenadas negativas: o canto inferior ' +
      'esquerdo do bloco fica no canto da area cortada (X %s Y %s, %s x %s mm); Z0 no topo do bloco',
      [FmtMM(CB.MinX), FmtMM(CB.MinY), FmtMM(Result.W), FmtMM(Result.H)]);
  end;
end;

procedure BlockPointInProgram(const B: TBlockPlacement; P: TBlockPoint; out PX, PY: Double);
begin
  PX := B.X0; PY := B.Y0;
  case P of
    bpBottomRight: PX := B.X0 + B.W;
    bpTopLeft: PY := B.Y0 + B.H;
    bpTopRight: begin PX := B.X0 + B.W; PY := B.Y0 + B.H; end;
    bpCenter: begin PX := B.X0 + B.W / 2; PY := B.Y0 + B.H / 2; end;
  end;
end;

procedure ZeroXYFromBlock(MX, MY: Double; const B: TBlockPlacement; P: TBlockPoint; out ZX, ZY: Double);
var PX, PY: Double;
begin
  BlockPointInProgram(B, P, PX, PY);
  ZX := MX - PX;
  ZY := MY - PY;
end;

function ZeroZFromTouch(TouchZ: Double; const B: TBlockPlacement): Double;
begin
  Result := TouchZ - B.Top;
end;

function G92ForBlockXY(CurX, CurY, MX, MY: Double; const B: TBlockPlacement; P: TBlockPoint): string;
var PX, PY: Double;
begin
  BlockPointInProgram(B, P, PX, PY);
  { nova coordenada = antiga - zero; a maquina em Cur passa a valer Cur - zero }
  Result := 'G92 X' + FmtMM(CurX - MX + PX) + ' Y' + FmtMM(CurY - MY + PY);
end;

function G92ForTop(CurZ, TouchZ: Double; const B: TBlockPlacement): string;
begin
  Result := 'G92 Z' + FmtMM(CurZ - TouchZ + B.Top);
end;

function BlockTop(const B: TBlockPlacement; Thickness: Double): Double;
begin
  if B.DatumTable and (Thickness > 0) then Result := Thickness else Result := B.Top;
end;

function CheckCutDepth(const B: TBlockPlacement; Thickness, Clearance: Double;
  out Depth, Allowed: Double; out Msg: string): Boolean;
begin
  Clearance := Max(MIN_DEPTH_CLEARANCE, Clearance);
  Depth := 0; Allowed := 0; Msg := '';
  if not B.HasCut then Exit(True);
  Depth := BlockTop(B, Thickness) - B.MinZ;
  Allowed := Thickness - Clearance;
  if Thickness <= 0 then
  begin
    Msg := 'Informe a espessura do bloco para conferir a profundidade do corte.';
    Exit(True);
  end;
  Result := Depth <= Allowed + 1E-6;
  if Result then
    Msg := Format('Profundidade do corte %s mm: cabe no bloco de %s mm com folga de %s mm.',
      [FmtMM(Depth), FmtMM(Thickness), FmtMM(Thickness - Depth)])
  else
    Msg := Format('O corte desce %s mm, mas o bloco tem %s mm e a folga minima e %s mm (maximo %s mm): ' +
      'a fresa passaria do bloco e pode quebrar.', [FmtMM(Depth), FmtMM(Thickness), FmtMM(Clearance), FmtMM(Allowed)]);
end;

initialization
  InvFS := DefaultFormatSettings;
  InvFS.DecimalSeparator := '.';
end.
