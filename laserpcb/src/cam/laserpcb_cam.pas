unit laserpcb_cam;

{ Geracao de trajetorias do LaserPCB a partir das mascaras raster.

  - LPIsolation: contornos de isolacao ao redor do cobre (como o
    "Isolation Routing" do FlatCAM): passada k a  Spot/2 + k*Passo  do
    cobre, Passo = Spot*(1 - Sobreposicao). Ilhas mais proximas que 2x a
    distancia se unem (contorno unico), como em um offset de poligonos.
  - LPHatch: linhas de varredura (preenchimento) dentro de uma mascara,
    recuadas Spot/2 da borda (compensacao do feixe), bidirecionais, a 0 ou
    90 graus; usado para remover cobre, expor pads (mascara) e gravar
    serigrafia.
  - LPRemoveCopperMask: area a remover = placa - (cobre dilatado de uma
    folga). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, laserpcb_geom, laserpcb_raster;

type
  TLPHatchDir = (hdHorizontal, hdVertical);

{ Copper: mascara com cobre = 1. Board (opcional): limita a area (1 = placa). }
function LPIsolation(Copper, Board: TLPMask; Spot: Double; Passes: Integer;
  Overlap: Double; Tol: Double): TLPPaths;

{ linhas de preenchimento dentro de Area (=1) recuadas Inset; Interval em mm }
function LPHatch(Area: TLPMask; Interval, Inset: Double; Dir: TLPHatchDir;
  Bidirectional: Boolean): TLPPaths;

{ area de cobre a remover: dentro da placa e mais longe que Clearance do cobre }
function LPRemoveCopperMask(Copper, Board: TLPMask; Clearance: Double): TLPMask;

{ mascara erodida (Inset > 0) ou dilatada (Inset < 0) }
function LPOffsetMask(M: TLPMask; Offset: Double): TLPMask;

{ corta caminhos fechados deixando pontes (tabs) de largura TabW; Count por caminho }
function LPAddTabs(const P: TLPPaths; Count: Integer; TabW: Double): TLPPaths;

implementation

function LPIsolation(Copper, Board: TLPMask; Spot: Double; Passes: Integer;
  Overlap: Double; Tol: Double): TLPPaths;
var
  F: TLPField;
  K, I, J: Integer;
  Level, Step: Double;
  C: TLPPaths;
  Inside: Boolean;
  Q: TLPPath;
begin
  Result := nil;
  if Passes < 1 then Passes := 1;
  Step := Spot * (1 - EnsureRange(Overlap, 0, 0.9));
  F := TLPField.Create(Copper, 1);
  try
    for K := 0 to Passes - 1 do
    begin
      Level := Spot / 2 + K * Step;
      C := LPIsoContours(F, Level, Tol);
      for I := 0 to High(C) do
      begin
        Q := C[I];
        { descarta contornos totalmente fora da placa }
        if Board <> nil then
        begin
          Inside := False;
          for J := 0 to High(Q) do
            if Board.Get(Board.ColOf(Q[J].X), Board.RowOf(Q[J].Y)) <> 0 then
            begin
              Inside := True;
              Break;
            end;
          if not Inside then Continue;
        end;
        LPAddPath(Result, Q);
      end;
    end;
  finally
    F.Free;
  end;
end;

function LPOffsetMask(M: TLPMask; Offset: Double): TLPMask;
var
  F: TLPField;
  I: Integer;
begin
  Result := TLPMask.CreateLike(M);
  if Offset = 0 then
  begin
    Move(M.Data[0], Result.Data[0], Length(M.Data));
    Exit;
  end;
  if Offset > 0 then
  begin
    { erosao: pixels dentro a mais de Offset da borda }
    F := TLPField.Create(M, 0);
    try
      for I := 0 to High(M.Data) do
        if (M.Data[I] <> 0) and (F.D[I] > Offset) then Result.Data[I] := 1;
    finally
      F.Free;
    end;
  end
  else
  begin
    F := TLPField.Create(M, 1);
    try
      for I := 0 to High(M.Data) do
        if F.D[I] <= -Offset then Result.Data[I] := 1;
    finally
      F.Free;
    end;
  end;
end;

function LPHatch(Area: TLPMask; Interval, Inset: Double; Dir: TLPHatchDir;
  Bidirectional: Boolean): TLPPaths;
var
  M: TLPMask;
  Lines, Segs, I, J, K, S0, Count: Integer;
  Pos0, PosV: Double;
  Seg: TLPPath;
  Row: TLPPaths;
  Flip: Boolean;

  function At(A, B: Integer): Boolean; inline;
  begin
    if Dir = hdHorizontal then Result := M.Get(A, B) <> 0
    else Result := M.Get(B, A) <> 0;
  end;

begin
  Result := nil;
  if Interval <= 0 then Exit;
  if Inset > 0 then M := LPOffsetMask(Area, Inset) else M := Area;
  try
    if Dir = hdHorizontal then
    begin
      Lines := M.Height;
      Count := M.Width;
      Pos0 := M.Y0;
    end
    else
    begin
      Lines := M.Width;
      Count := M.Height;
      Pos0 := M.X0;
    end;
    Flip := False;
    PosV := Pos0 + Interval / 2;
    while PosV < Pos0 + Lines * M.Res do
    begin
      J := Floor((PosV - Pos0) / M.Res);
      Row := nil;
      K := 0;
      while K < Count do
      begin
        while (K < Count) and not At(K, J) do Inc(K);
        if K >= Count then Break;
        S0 := K;
        while (K < Count) and At(K, J) do Inc(K);
        Seg := nil;
        if Dir = hdHorizontal then
        begin
          LPAddPoint(Seg, M.X0 + S0 * M.Res, PosV);
          LPAddPoint(Seg, M.X0 + K * M.Res, PosV);
        end
        else
        begin
          LPAddPoint(Seg, PosV, M.Y0 + S0 * M.Res);
          LPAddPoint(Seg, PosV, M.Y0 + K * M.Res);
        end;
        LPAddPath(Row, Seg);
      end;
      if Length(Row) > 0 then
      begin
        Segs := Length(Row);
        if Bidirectional and Flip then
          for I := Segs - 1 downto 0 do
            LPAddPath(Result, LPReversed(Row[I]))
        else
          for I := 0 to Segs - 1 do
            LPAddPath(Result, Row[I]);
        Flip := not Flip;
      end;
      PosV := PosV + Interval;
    end;
  finally
    if M <> Area then M.Free;
  end;
end;

function LPRemoveCopperMask(Copper, Board: TLPMask; Clearance: Double): TLPMask;
var
  F: TLPField;
  I: Integer;
begin
  Result := TLPMask.CreateLike(Copper);
  F := TLPField.Create(Copper, 1);
  try
    for I := 0 to High(Result.Data) do
      if (F.D[I] > Clearance) and ((Board = nil) or (Board.Data[I] <> 0)) then
        Result.Data[I] := 1;
  finally
    F.Free;
  end;
end;

function LPAddTabs(const P: TLPPaths; Count: Integer; TabW: Double): TLPPaths;
var
  I, K, N: Integer;
  L, Spacing, Pos, SegL, T, Acc: Double;
  Gaps: array of Double;
  Cur: TLPPath;
  InGap: Boolean;
  GapIdx: Integer;
  A, B: TLPPoint;

  function GapAt(D: Double): Boolean;
  var
    G: Integer;
  begin
    for G := 0 to High(Gaps) do
      if (D >= Gaps[G] - TabW / 2) and (D <= Gaps[G] + TabW / 2) then Exit(True);
    Result := False;
  end;

begin
  Result := nil;
  for I := 0 to High(P) do
  begin
    L := LPPathLength(P[I]);
    if (Count <= 0) or (TabW <= 0) or not LPIsClosed(P[I]) or (L < Count * TabW * 3) then
    begin
      LPAddPath(Result, P[I]);
      Continue;
    end;
    Spacing := L / Count;
    SetLength(Gaps, Count);
    for K := 0 to Count - 1 do
      Gaps[K] := Spacing * (K + 0.5);
    { percorre amostrando em passos pequenos }
    Cur := nil;
    Acc := 0;
    InGap := GapAt(0);
    if not InGap then LPAddPoint(Cur, P[I][0].X, P[I][0].Y);
    for K := 1 to High(P[I]) do
    begin
      A := P[I][K - 1];
      B := P[I][K];
      SegL := LPDist(A, B);
      N := Max(1, Ceil(SegL / (TabW / 4)));
      for GapIdx := 1 to N do
      begin
        T := GapIdx / N;
        Pos := Acc + SegL * T;
        if GapAt(Pos) then
        begin
          if not InGap then
          begin
            LPAddPoint(Cur, A.X + (B.X - A.X) * T, A.Y + (B.Y - A.Y) * T);
            if Length(Cur) >= 2 then LPAddPath(Result, LPSimplify(Cur, 1e-6));
            Cur := nil;
            InGap := True;
          end;
        end
        else
        begin
          if InGap then
          begin
            Cur := nil;
            InGap := False;
          end;
          LPAddPoint(Cur, A.X + (B.X - A.X) * T, A.Y + (B.Y - A.Y) * T);
        end;
      end;
      Acc := Acc + SegL;
    end;
    if Length(Cur) >= 2 then LPAddPath(Result, LPSimplify(Cur, 1e-6));
  end;
end;

end.
