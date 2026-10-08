unit makerouter_sim;

{ Simulacao da remocao de material do MakeRouter.

  O material e uma grade de alturas (Z = 0 no topo, -Espessura na base). Cada
  movimento de corte varre a forma da ferramenta (reta, esferica, V) e baixa
  as celulas que ela alcanca. A resolucao se ajusta ao tamanho (limite de
  celulas) e a imagem sombreada (RGB) e gerada aqui, sem LCL; a interface so
  copia os pixels.

  E uma previa visual e de conferencia (volume removido, cortes abaixo da base),
  nao uma simulacao fisica de forcas. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, makerouter_types, makerouter_project;

const
  MR_SIM_MAX_CELLS = 2500000;

type
  TMRPixels = array of LongWord;   { $00RRGGBB }

  TMRStock = class
  private
    FCols, FRows: Integer;
    FCell, FW, FH, FT: Double;
    procedure Stamp(X, Y, Z0: Double; const Tool: TMRTool);
  public
    Z: array of Single;
    BelowBase: Integer;     { celulas cortadas abaixo da base do material }
    procedure Init(const M: TMRMaterial; CellMM: Double = 0);
    procedure Reset;
    { aplica os movimentos de um percurso; Upto < 0 = todos }
    procedure Apply(const Moves: TMRMoves; const Tool: TMRTool; Upto: Integer = -1);
    function Height(C, R: Integer): Single; inline;
    function RemovedVolume: Double;   { mm3 }
    { imagem sombreada Width x Height pixels (vista de cima, luz obliqua) }
    function Render(AWidth, AHeight: Integer; WoodIndex: Integer): TMRPixels;
    property Cols: Integer read FCols;
    property Rows: Integer read FRows;
    property Cell: Double read FCell;
  end;

implementation

procedure TMRStock.Init(const M: TMRMaterial; CellMM: Double);
begin
  FW := Max(1, M.Width); FH := Max(1, M.Height); FT := Max(0.1, M.Thickness);
  if CellMM <= 0 then
    CellMM := Max(0.25, Sqrt(FW * FH / MR_SIM_MAX_CELLS));
  FCell := CellMM;
  FCols := Max(1, Ceil(FW / FCell));
  FRows := Max(1, Ceil(FH / FCell));
  SetLength(Z, FCols * FRows);
  Reset;
end;

procedure TMRStock.Reset;
var I: Integer;
begin
  for I := 0 to High(Z) do Z[I] := 0;
  BelowBase := 0;
end;

function TMRStock.Height(C, R: Integer): Single;
begin
  Result := Z[R * FCols + C];
end;

procedure TMRStock.Stamp(X, Y, Z0: Double; const Tool: TMRTool);
var C, R, C0, C1, R0, R1, Idx: Integer; Rad, D2, PX, PY, TZ, TanH, D: Double;
begin
  Rad := Tool.Diameter / 2;
  if Tool.Kind in [tkVBit, tkEngrave] then
  begin
    TanH := Tan(DegToRad(Max(5, Tool.Angle) / 2));
    Rad := Min(Rad, Max(0, -Z0) * TanH);
    if Rad < FCell * 0.5 then Rad := FCell * 0.5;   { marca o risco minimo }
  end
  else TanH := 0;
  C0 := Max(0, Floor((X - Rad) / FCell)); C1 := Min(FCols - 1, Floor((X + Rad) / FCell));
  R0 := Max(0, Floor((Y - Rad) / FCell)); R1 := Min(FRows - 1, Floor((Y + Rad) / FCell));
  for R := R0 to R1 do
  begin
    PY := (R + 0.5) * FCell - Y;
    for C := C0 to C1 do
    begin
      PX := (C + 0.5) * FCell - X;
      D2 := PX * PX + PY * PY;
      if D2 > Rad * Rad then Continue;
      case Tool.Kind of
        tkBallNose: TZ := Z0 + Rad - Sqrt(Max(0, Rad * Rad - D2));
        tkVBit, tkEngrave:
          begin
            D := Sqrt(D2);
            if TanH > 0 then TZ := Z0 + D / TanH else TZ := Z0;
          end;
      else
        TZ := Z0;
      end;
      Idx := R * FCols + C;
      if TZ < Self.Z[Idx] then
      begin
        if (TZ < -FT - 0.01) and (Self.Z[Idx] >= -FT - 0.01) then Inc(BelowBase);
        Self.Z[Idx] := Max(TZ, -FT - 2);
      end;
    end;
  end;
end;

procedure TMRStock.Apply(const Moves: TMRMoves; const Tool: TMRTool; Upto: Integer);
var I, K, N: Integer; A, B: TMRMove; L, Stp: Double;
begin
  if Upto < 0 then Upto := High(Moves);
  Stp := FCell * 0.5;
  for I := 1 to Min(Upto, High(Moves)) do
  begin
    A := Moves[I - 1]; B := Moves[I];
    if B.Rapid then Continue;
    if (A.Z >= 0) and (B.Z >= 0) then Continue;
    L := Hypot(B.X - A.X, B.Y - A.Y);
    N := Max(1, Ceil(L / Stp));
    for K := 0 to N do
      Stamp(A.X + (B.X - A.X) * K / N, A.Y + (B.Y - A.Y) * K / N,
        A.Z + (B.Z - A.Z) * K / N, Tool);
  end;
end;

function TMRStock.RemovedVolume: Double;
var I: Integer;
begin
  Result := 0;
  for I := 0 to High(Z) do Result := Result - Max(-FT, Z[I]);
  Result := Result * FCell * FCell;
end;

function Mix(C1, C2: LongWord; T: Double): LongWord;
var R, G, B: Integer;
begin
  T := EnsureRange(T, 0, 1);
  { cores TColor: $00BBGGRR }
  R := Round((C1 and $FF) * (1 - T) + (C2 and $FF) * T);
  G := Round(((C1 shr 8) and $FF) * (1 - T) + ((C2 shr 8) and $FF) * T);
  B := Round(((C1 shr 16) and $FF) * (1 - T) + ((C2 shr 16) and $FF) * T);
  Result := LongWord(R) or (LongWord(G) shl 8) or (LongWord(B) shl 16);
end;

function Shade(C: LongWord; F: Double): LongWord;
var R, G, B: Integer;
begin
  F := EnsureRange(F, 0, 1.4);
  R := Min(255, Round((C and $FF) * F));
  G := Min(255, Round(((C shr 8) and $FF) * F));
  B := Min(255, Round(((C shr 16) and $FF) * F));
  Result := LongWord(R) or (LongWord(G) shl 8) or (LongWord(B) shl 16);
end;

function TMRStock.Render(AWidth, AHeight: Integer; WoodIndex: Integer): TMRPixels;
var X, Y, C, R, K, MaxK, Stp: Integer; Sx, Sy, Zc, Zx, Zy, NX, NY, NZ, L, Lam, Depth, Grain, Sh: Double;
  Light, Dark, Col: LongWord;
begin
  Result := nil;
  if (AWidth <= 0) or (AHeight <= 0) or (FCols = 0) then Exit;
  SetLength(Result, AWidth * AHeight);
  WoodIndex := EnsureRange(WoodIndex, 0, High(MR_WOODS));
  Light := MR_WOOD_LIGHT[WoodIndex]; Dark := MR_WOOD_DARK[WoodIndex];
  Sx := FCols / AWidth; Sy := FRows / AHeight;
  { sombra: procura ate 10 mm na direcao da luz, em passos de ~0,5 mm }
  MaxK := Max(1, Round(Min(10, FT) / FCell));
  Stp := Max(1, Round(0.5 / FCell));
  for Y := 0 to AHeight - 1 do
  begin
    R := EnsureRange(Trunc((AHeight - 1 - Y) * Sy), 0, FRows - 1);  { Y para cima }
    for X := 0 to AWidth - 1 do
    begin
      C := EnsureRange(Trunc(X * Sx), 0, FCols - 1);
      Zc := Self.Z[R * FCols + C];
      Zx := Self.Z[R * FCols + Min(FCols - 1, C + 1)] - Self.Z[R * FCols + Max(0, C - 1)];
      Zy := Self.Z[Min(FRows - 1, R + 1) * FCols + C] - Self.Z[Max(0, R - 1) * FCols + C];
      { normal da superficie (escala exagera o relevo para leitura) }
      NX := -Zx / (2 * FCell); NY := -Zy / (2 * FCell); NZ := 1;
      L := Sqrt(NX * NX + NY * NY + NZ * NZ);
      { luz vinda de cima/esquerda/frente }
      Lam := (NX * -0.45 + NY * 0.55 + NZ * 0.70) / L;
      Depth := EnsureRange(-Zc / FT, 0, 1);
      Grain := 0.06 * Sin((R * FCell) * 0.9 + Sin((C * FCell) * 0.05) * 3);
      Col := Mix(Light, Dark, Depth * 1.6 + Grain + 0.06);
      if Zc < -FT - 0.01 then Col := $3C3CC8;   { abaixo da base: vermelho }
      { sombra projetada pela luz (vem de cima/esquerda) }
      Sh := 1;
      K := Stp;
      while K <= MaxK do
      begin
        if (C - K < 0) or (R + K >= FRows) then Break;
        if Self.Z[(R + K) * FCols + C - K] > Zc + K * FCell * 1.0 + 0.2 then
        begin
          Sh := 0.7;
          Break;
        end;
        Inc(K, Stp);
      end;
      Result[Y * AWidth + X] := Shade(Col, (0.55 + 0.6 * Max(0, Lam)) * Sh);
    end;
  end;
end;

end.
