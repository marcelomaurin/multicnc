unit multicad_triangulate;

{ MultiCAD - triangulacao de poligono com furos (tampas da extrusao e da
  revolucao).

  Metodo: cada furo e ligado ao contorno por uma ponte (vertice mais a
  direita do furo -> vertice visivel mais proximo), formando um poligono
  simples; depois, recorte de orelhas (ear clipping).
  Entrada: externo anti-horario, furos horarios (como multicad_profile
  entrega). Saida: triangulos anti-horarios em indices de Pts, onde Pts e
  o externo seguido dos furos, na ordem recebida. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, multicad_types;

type
  TCadPoly2 = array of TCadVec2;
  TCadPoly2Array = array of TCadPoly2;
  TCadTriIdx = record
    A, B, C: Integer;
  end;
  TCadTriIdxArray = array of TCadTriIdx;

{ False se a geometria for invalida (menos de 3 pontos, area nula) ou se
  precisou forcar orelhas (poligono que se cruza): AError explica. Mesmo
  com False, Tris pode ter o resultado aproximado. }
function CadTriangulate(const Outer: TCadPoly2; const Holes: TCadPoly2Array;
  out Pts: TCadPoly2; out Tris: TCadTriIdxArray; out AError: string): Boolean;
function CadPoly2Area(const P: TCadPoly2): Double;

implementation

function CadPoly2Area(const P: TCadPoly2): Double;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 0 to High(P) do
  begin
    J := (I + 1) mod Length(P);
    Result := Result + P[I].X * P[J].Y - P[J].X * P[I].Y;
  end;
  Result := Result / 2;
end;

function Cross3(const A, B, C: TCadVec2): Double;
begin
  Result := (B.X - A.X) * (C.Y - A.Y) - (B.Y - A.Y) * (C.X - A.X);
end;

function SamePt(const A, B: TCadVec2): Boolean;
begin
  Result := (Abs(A.X - B.X) < 1E-12) and (Abs(A.Y - B.Y) < 1E-12);
end;

{ Segmentos AB e CD se cruzam no interior (toque em extremidade nao conta). }
function ProperCross(const A, B, C, D: TCadVec2): Boolean;
var
  D1, D2, D3, D4: Double;
begin
  D1 := Cross3(C, D, A);
  D2 := Cross3(C, D, B);
  D3 := Cross3(A, B, C);
  D4 := Cross3(A, B, D);
  Result := (((D1 > 1E-12) and (D2 < -1E-12)) or ((D1 < -1E-12) and (D2 > 1E-12))) and
    (((D3 > 1E-12) and (D4 < -1E-12)) or ((D3 < -1E-12) and (D4 > 1E-12)));
end;

function InPoly(const P: TCadVec2; const Poly: TCadPoly2): Boolean;
var
  I, J: Integer;
begin
  Result := False;
  J := High(Poly);
  for I := 0 to High(Poly) do
  begin
    if ((Poly[I].Y > P.Y) <> (Poly[J].Y > P.Y)) and
      (P.X < (Poly[J].X - Poly[I].X) * (P.Y - Poly[I].Y) / (Poly[J].Y - Poly[I].Y) + Poly[I].X) then
      Result := not Result;
    J := I;
  end;
end;

{ Ponto dentro (ou na borda) do triangulo anti-horario ABC. }
function InTri(const P, A, B, C: TCadVec2): Boolean;
begin
  Result := (Cross3(A, B, P) >= -1E-12) and (Cross3(B, C, P) >= -1E-12) and
    (Cross3(C, A, P) >= -1E-12);
end;

function CadTriangulate(const Outer: TCadPoly2; const Holes: TCadPoly2Array;
  out Pts: TCadPoly2; out Tris: TCadTriIdxArray; out AError: string): Boolean;
var
  HoleStart: array of Integer;
  Order: array of Integer;
  Idx: array of Integer;
  I, J, K, H, N, Total, M, Best, BestK, Pass, Guard, NT: Integer;
  BestD, D: Double;
  Mid: TCadVec2;
  Ok, Forced: Boolean;
  Merged: array of Integer;
  Prev, Next: array of Integer;
  Alive: Integer;
  Cur, P0, P2: Integer;

  function HoleOf(V: Integer): Integer;
  var
    Q: Integer;
  begin
    Result := -1;
    for Q := High(HoleStart) downto 0 do
      if V >= HoleStart[Q] then
        Exit(Q);
  end;

  function SegmentClear(VA, VB: Integer): Boolean;
  var
    Q, R, Len: Integer;
    A, B: TCadVec2;
  begin
    { contra o poligono atual (ja com as pontes) }
    A := Pts[VA];
    B := Pts[VB];
    Len := Length(Idx);
    for Q := 0 to Len - 1 do
      if ProperCross(A, B, Pts[Idx[Q]], Pts[Idx[(Q + 1) mod Len]]) then
        Exit(False);
    { contra os furos que ainda nao foram ligados }
    for Q := 0 to High(Holes) do
      for R := 0 to High(Holes[Q]) do
        if ProperCross(A, B, Holes[Q][R], Holes[Q][(R + 1) mod Length(Holes[Q])]) then
          Exit(False);
    Result := True;
  end;

  function IsEar(B: Integer): Boolean;
  var
    A, C, Q: Integer;
  begin
    A := Prev[B];
    C := Next[B];
    if Cross3(Pts[Merged[A]], Pts[Merged[B]], Pts[Merged[C]]) <= 1E-14 then
      Exit(False);
    Q := Next[C];
    while Q <> A do
    begin
      if not SamePt(Pts[Merged[Q]], Pts[Merged[A]]) and
        not SamePt(Pts[Merged[Q]], Pts[Merged[B]]) and
        not SamePt(Pts[Merged[Q]], Pts[Merged[C]]) and
        InTri(Pts[Merged[Q]], Pts[Merged[A]], Pts[Merged[B]], Pts[Merged[C]]) then
        Exit(False);
      Q := Next[Q];
    end;
    Result := True;
  end;

  procedure Emit(B: Integer);
  begin
    if NT >= Length(Tris) then
      SetLength(Tris, Max(16, NT * 2));
    Tris[NT].A := Merged[Prev[B]];
    Tris[NT].B := Merged[B];
    Tris[NT].C := Merged[Next[B]];
    Inc(NT);
    Next[Prev[B]] := Next[B];
    Prev[Next[B]] := Prev[B];
    Dec(Alive);
  end;

begin
  Result := False;
  AError := '';
  Pts := nil;
  Tris := nil;
  if Length(Outer) < 3 then
  begin
    AError := 'Contorno com menos de 3 pontos';
    Exit;
  end;
  if Abs(CadPoly2Area(Outer)) < 1E-12 then
  begin
    AError := 'Contorno com área nula';
    Exit;
  end;
  { pontos: externo + furos }
  Total := Length(Outer);
  SetLength(HoleStart, Length(Holes));
  for H := 0 to High(Holes) do
  begin
    HoleStart[H] := Total;
    Inc(Total, Length(Holes[H]));
  end;
  SetLength(Pts, Total);
  for I := 0 to High(Outer) do
    Pts[I] := Outer[I];
  for H := 0 to High(Holes) do
    for I := 0 to High(Holes[H]) do
      Pts[HoleStart[H] + I] := Holes[H][I];
  SetLength(Idx, Length(Outer));
  for I := 0 to High(Outer) do
    Idx[I] := I;

  { furos em ordem de x maximo decrescente }
  SetLength(Order, Length(Holes));
  for H := 0 to High(Holes) do
    Order[H] := H;
  for I := 0 to High(Order) do
    for J := I + 1 to High(Order) do
    begin
      D := -1E300;
      for K := 0 to High(Holes[Order[I]]) do D := Max(D, Holes[Order[I]][K].X);
      BestD := -1E300;
      for K := 0 to High(Holes[Order[J]]) do BestD := Max(BestD, Holes[Order[J]][K].X);
      if BestD > D then
      begin
        K := Order[I]; Order[I] := Order[J]; Order[J] := K;
      end;
    end;

  for Pass := 0 to High(Order) do
  begin
    H := Order[Pass];
    if Length(Holes[H]) < 3 then
      Continue;
    { vertice do furo mais a direita }
    M := 0;
    for I := 1 to High(Holes[H]) do
      if Holes[H][I].X > Holes[H][M].X then
        M := I;
    { vertice visivel mais proximo no poligono atual }
    Best := -1;
    BestK := -1;
    BestD := 1E300;
    for K := 0 to High(Idx) do
    begin
      D := Sqr(Pts[Idx[K]].X - Holes[H][M].X) + Sqr(Pts[Idx[K]].Y - Holes[H][M].Y);
      if D >= BestD then
        Continue;
      if not SegmentClear(HoleStart[H] + M, Idx[K]) then
        Continue;
      Mid := V2((Pts[Idx[K]].X + Holes[H][M].X) / 2, (Pts[Idx[K]].Y + Holes[H][M].Y) / 2);
      Ok := InPoly(Mid, Outer);
      for J := 0 to High(Holes) do
        if Ok and InPoly(Mid, Holes[J]) then
          Ok := False;
      if not Ok then
        Continue;
      BestD := D;
      Best := Idx[K];
      BestK := K;
    end;
    if Best < 0 then
    begin
      AError := 'Não foi possível ligar um furo ao contorno (furo encostado ou cruzando)';
      Exit;
    end;
    { novo poligono: ... V, M, (furo), M, V, ... }
    N := Length(Holes[H]);
    SetLength(Merged, 0);
    SetLength(Merged, Length(Idx) + N + 2);
    J := 0;
    for K := 0 to BestK do
    begin
      Merged[J] := Idx[K];
      Inc(J);
    end;
    for I := 0 to N do
    begin
      Merged[J] := HoleStart[H] + ((M + I) mod N);
      Inc(J);
    end;
    Merged[J] := Best;
    Inc(J);
    for K := BestK + 1 to High(Idx) do
    begin
      Merged[J] := Idx[K];
      Inc(J);
    end;
    SetLength(Merged, J);
    Idx := Copy(Merged);
  end;

  { recorte de orelhas }
  Merged := Copy(Idx);
  N := Length(Merged);
  SetLength(Prev, N);
  SetLength(Next, N);
  for I := 0 to N - 1 do
  begin
    Prev[I] := (I + N - 1) mod N;
    Next[I] := (I + 1) mod N;
  end;
  Alive := N;
  NT := 0;
  Forced := False;
  Cur := 0;
  Guard := 0;
  while Alive > 3 do
  begin
    if IsEar(Cur) then
    begin
      P0 := Prev[Cur];
      Emit(Cur);
      Cur := P0;
      Guard := 0;
      Continue;
    end;
    Cur := Next[Cur];
    Inc(Guard);
    if Guard > Alive then
    begin
      { nenhuma orelha: tira o vertice mais convexo (ou degenerado) }
      Best := Cur;
      BestD := -1E300;
      K := Cur;
      repeat
        D := Cross3(Pts[Merged[Prev[K]]], Pts[Merged[K]], Pts[Merged[Next[K]]]);
        if D > BestD then
        begin
          BestD := D;
          Best := K;
        end;
        K := Next[K];
      until K = Cur;
      if BestD > 1E-14 then
        Forced := True;
      P2 := Prev[Best];
      if BestD > 1E-14 then
        Emit(Best)
      else
      begin
        { vertice colinear/degenerado: remove sem triangulo }
        Next[Prev[Best]] := Next[Best];
        Prev[Next[Best]] := Prev[Best];
        Dec(Alive);
      end;
      Cur := P2;
      Guard := 0;
    end;
  end;
  if Alive = 3 then
    if Cross3(Pts[Merged[Prev[Cur]]], Pts[Merged[Cur]], Pts[Merged[Next[Cur]]]) > 1E-14 then
      Emit(Cur);
  SetLength(Tris, NT);
  if Forced then
  begin
    AError := 'Contorno que cruza a si mesmo: triangulação aproximada';
    Exit;
  end;
  Result := True;
end;

end.
