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

function LPClipPathsToMask(const Paths: TLPPaths; Board: TLPMask): TLPPaths;

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

function LPClipPathsToMask(const Paths: TLPPaths; Board: TLPMask): TLPPaths;
var I, J, K, N, Col, Lo, Hi: Integer; A, B, Q, StartQ, EndQ: TLPPoint;
  TS: array of Double; DX, DY, T, Mid, Eps: Double; Cur: TLPPath;
  procedure Sort(L, R: Integer);
  var X, V: Double; U, W: Integer;
  begin
    U := L; W := R; X := TS[(L + R) div 2];
    repeat
      while TS[U] < X do Inc(U);
      while TS[W] > X do Dec(W);
      if U <= W then begin V := TS[U]; TS[U] := TS[W]; TS[W] := V; Inc(U); Dec(W); end;
    until U > W;
    if L < W then Sort(L, W);
    if U < R then Sort(U, R);
  end;
  procedure AddT(V: Double);
  begin
    if (V <= 0) or (V >= 1) then Exit;
    if N = Length(TS) then SetLength(TS, Max(32, N * 2));
    TS[N] := V; Inc(N);
  end;
  function At(V: Double): TLPPoint;
  begin Result := LPPoint(A.X + V * DX, A.Y + V * DY); end;
  function Inside(const P: TLPPoint): Boolean;
  begin Result := Board.Get(Board.ColOf(P.X), Board.RowOf(P.Y)) <> 0; end;
  procedure Put(const P: TLPPoint);
  var M: Integer; U, V: TLPPoint;
  begin
    M := Length(Cur);
    if (M > 0) and (LPDist(Cur[M-1], P) < 1e-10) then Exit;
    if M >= 2 then
    begin
      U := Cur[M-2]; V := Cur[M-1];
      if (Abs((V.X-U.X)*(P.Y-V.Y) - (V.Y-U.Y)*(P.X-V.X)) < 1e-12) and
        ((V.X-U.X)*(P.X-V.X) + (V.Y-U.Y)*(P.Y-V.Y) >= 0) then
      begin Cur[M-1] := P; Exit; end;
    end;
    LPAddPoint(Cur, P.X, P.Y);
  end;
  procedure Flush;
  begin
    if (Length(Cur) >= 2) and (LPPathLength(Cur) > 1e-8) then LPAddPath(Result, Cur);
    Cur := nil;
  end;
begin
  Result := nil;
  if Board = nil then Exit(Paths);
  for I := 0 to High(Paths) do
  begin
    Cur := nil;
    for J := 1 to High(Paths[I]) do
    begin
      A := Paths[I][J-1]; B := Paths[I][J];
      DX := B.X - A.X; DY := B.Y - A.Y;
      if Hypot(DX, DY) < 1e-12 then Continue;
      SetLength(TS, 32); TS[0] := 0; TS[1] := 1; N := 2;
      { Todas as intersecoes da linha com a grade: nao salta furos estreitos.
        A classificacao usa o interior de cada intervalo, sem aproximar a borda. }
      if Abs(DX) > 1e-12 then
      begin
        Lo := Max(0, Ceil((Min(A.X,B.X)-Board.X0)/Board.Res));
        Hi := Min(Board.Width, Floor((Max(A.X,B.X)-Board.X0)/Board.Res));
        for Col := Lo to Hi do AddT((Board.X0 + Col*Board.Res - A.X)/DX);
      end;
      if Abs(DY) > 1e-12 then
      begin
        Lo := Max(0, Ceil((Min(A.Y,B.Y)-Board.Y0)/Board.Res));
        Hi := Min(Board.Height, Floor((Max(A.Y,B.Y)-Board.Y0)/Board.Res));
        for Col := Lo to Hi do AddT((Board.Y0 + Col*Board.Res - A.Y)/DY);
      end;
      Sort(0, N-1);
      for K := 0 to N-2 do
      begin
        if TS[K+1] - TS[K] < 1e-14 then Continue;
        Mid := (TS[K] + TS[K+1])/2; Q := At(Mid);
        if not Inside(Q) then begin Flush; Continue; end;
        Eps := Min((TS[K+1]-TS[K])*0.01, 1e-7/Hypot(DX,DY));
        T := TS[K]; StartQ := At(T);
        if not Inside(StartQ) then StartQ := At(T + Eps);
        T := TS[K+1]; EndQ := At(T);
        if not Inside(EndQ) then EndQ := At(T - Eps);
        Put(StartQ); Put(EndQ);
      end;
    end;
    Flush;
  end;
end;


function LPIsolation(Copper, Board: TLPMask; Spot: Double; Passes: Integer;
  Overlap: Double; Tol: Double): TLPPaths;
var
  F: TLPField;
  K: Integer;
  Level, Step: Double;
  C: TLPPaths;
begin
  Result := nil;
  if (Copper = nil) or IsNan(Spot) or IsInfinite(Spot) or (Spot <= 0) or
    (Passes < 1) or (Passes > 1000) or IsNan(Overlap) or IsInfinite(Overlap) or
    (Overlap < 0) or (Overlap > 0.9) or IsNan(Tol) or IsInfinite(Tol) or (Tol < 0) then
    raise Exception.Create('Parametros de isolacao invalidos');
  if Board <> nil then Copper.RequireSameGrid(Board);
  Step := Spot * (1 - Overlap);
  F := TLPField.Create(Copper, 1);
  try
    for K := 0 to Passes - 1 do
    begin
      Level := Spot / 2 + K * Step;
      C := LPIsoContours(F, Level, Tol);
      C := LPClipPathsToMask(C, Board);
      LPAddPaths(Result, C);
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
  if (Copper = nil) or IsNan(Clearance) or IsInfinite(Clearance) or (Clearance < 0) then
    raise Exception.Create('Folga de cobre invalida');
  if Board <> nil then Copper.RequireSameGrid(Board);
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
