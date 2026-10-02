unit multisuite_geometry;

{$mode objfpc}{$H+}

{ Geometria 2D compartilhada da suite (MultiCAM, MultiSlicer, LaserArt).

  - area com sinal, orientacao, perimetro, limites;
  - ponto em poligono (regra de winding, robusta para poligonos concavos);
  - offset de poligono com juncoes arredondadas ou em quina (miter), usado
    na compensacao de raio da ferramenta (CAM) e nos perimetros (slicer);
  - recorte de polilinhas por poligono (preenchimentos/infill);
  - montagem de contornos fechados a partir de segmentos soltos.

  O offset trata poligonos simples (sem auto-intersecao). Para offsets
  internos maiores que a menor espessura da peca o resultado colapsa e e
  devolvido vazio - comportamento esperado em pockets. }

interface

uses Math;

type
  TPoint2D = record
    X, Y: Double;
  end;
  TPolygon2D = array of TPoint2D;
  TPolygons2D = array of TPolygon2D;

  TJoinType = (jtRound, jtMiter, jtSquare);

  TSegment2D = record
    A, B: TPoint2D;
  end;
  TSegments2D = array of TSegment2D;

function Pt(X, Y: Double): TPoint2D; inline;
function PolygonArea(const P: TPolygon2D): Double;
function PolygonIsCCW(const P: TPolygon2D): Boolean;
function PolygonPerimeter(const P: TPolygon2D; Closed: Boolean = True): Double;
procedure PolygonBounds(const P: TPolygon2D; out MinX, MinY, MaxX, MaxY: Double);
function PointInPolygon(const Q: TPoint2D; const P: TPolygon2D): Boolean;
function PointInPolygons(const Q: TPoint2D; const Polys: TPolygons2D): Boolean;
function ReversePolygon(const P: TPolygon2D): TPolygon2D;
function RemoveDuplicatePoints(const P: TPolygon2D; Eps: Double = 1e-9): TPolygon2D;
function DistancePointSegment(const Q, A, B: TPoint2D): Double;
{ Remove vertices colineares (distancia a reta dos vizinhos <= Eps). }
function SimplifyCollinear(const P: TPolygon2D; Eps: Double = 1e-9): TPolygon2D;
function DistanceToPolygon(const Q: TPoint2D; const P: TPolygon2D): Double;

{ Delta > 0 expande, Delta < 0 contrai (independe da orientacao). }
function OffsetPolygon(const P: TPolygon2D; Delta: Double; Join: TJoinType = jtRound;
  MiterLimit: Double = 2.0; ArcTolerance: Double = 0.01): TPolygon2D;

{ Trechos da polilinha que ficam dentro da regiao (poligonos com regra
  par-impar: contornos internos viram furos). }
function ClipPolylineToRegion(const Line: TPolygon2D; const Region: TPolygons2D): TPolygons2D;

{ Une segmentos soltos (ex.: corte de triangulos por um plano) em contornos
  fechados. Tolerancia em mm para considerar extremidades coincidentes. }
function ChainSegments(const Segs: TSegments2D; Tol: Double = 1e-4): TPolygons2D;

implementation

function Pt(X, Y: Double): TPoint2D;
begin
  Result.X := X;
  Result.Y := Y;
end;

function PolygonArea(const P: TPolygon2D): Double;
var I, J: Integer;
begin
  Result := 0;
  if Length(P) < 3 then Exit;
  J := High(P);
  for I := 0 to High(P) do begin
    Result := Result + (P[J].X * P[I].Y - P[I].X * P[J].Y);
    J := I;
  end;
  Result := Result / 2;
end;

function PolygonIsCCW(const P: TPolygon2D): Boolean;
begin
  Result := PolygonArea(P) > 0;
end;

function PolygonPerimeter(const P: TPolygon2D; Closed: Boolean): Double;
var I: Integer;
begin
  Result := 0;
  for I := 1 to High(P) do Result := Result + Hypot(P[I].X - P[I - 1].X, P[I].Y - P[I - 1].Y);
  if Closed and (Length(P) > 2) then
    Result := Result + Hypot(P[0].X - P[High(P)].X, P[0].Y - P[High(P)].Y);
end;

procedure PolygonBounds(const P: TPolygon2D; out MinX, MinY, MaxX, MaxY: Double);
var I: Integer;
begin
  MinX := 0; MinY := 0; MaxX := 0; MaxY := 0;
  if Length(P) = 0 then Exit;
  MinX := P[0].X; MaxX := P[0].X; MinY := P[0].Y; MaxY := P[0].Y;
  for I := 1 to High(P) do begin
    MinX := Min(MinX, P[I].X); MaxX := Max(MaxX, P[I].X);
    MinY := Min(MinY, P[I].Y); MaxY := Max(MaxY, P[I].Y);
  end;
end;

function PointInPolygon(const Q: TPoint2D; const P: TPolygon2D): Boolean;
var I, J, Winding: Integer; IsLeft: Double;
begin
  Winding := 0;
  if Length(P) < 3 then Exit(False);
  J := High(P);
  for I := 0 to High(P) do begin
    IsLeft := (P[I].X - P[J].X) * (Q.Y - P[J].Y) - (Q.X - P[J].X) * (P[I].Y - P[J].Y);
    if P[J].Y <= Q.Y then begin
      if (P[I].Y > Q.Y) and (IsLeft > 0) then Inc(Winding);
    end else begin
      if (P[I].Y <= Q.Y) and (IsLeft < 0) then Dec(Winding);
    end;
    J := I;
  end;
  Result := Winding <> 0;
end;

function PointInPolygons(const Q: TPoint2D; const Polys: TPolygons2D): Boolean;
var I: Integer;
begin
  // par-impar entre contornos: ilhas e furos alternam
  Result := False;
  for I := 0 to High(Polys) do
    if PointInPolygon(Q, Polys[I]) then Result := not Result;
end;

function ReversePolygon(const P: TPolygon2D): TPolygon2D;
var I: Integer;
begin
  SetLength(Result, Length(P));
  for I := 0 to High(P) do Result[I] := P[High(P) - I];
end;

function RemoveDuplicatePoints(const P: TPolygon2D; Eps: Double): TPolygon2D;
var I, N: Integer;
begin
  SetLength(Result, Length(P));
  N := 0;
  for I := 0 to High(P) do
    if (N = 0) or (Hypot(P[I].X - Result[N - 1].X, P[I].Y - Result[N - 1].Y) > Eps) then begin
      Result[N] := P[I];
      Inc(N);
    end;
  if (N > 1) and (Hypot(Result[0].X - Result[N - 1].X, Result[0].Y - Result[N - 1].Y) <= Eps) then Dec(N);
  SetLength(Result, N);
end;

function DistancePointSegment(const Q, A, B: TPoint2D): Double;
var DX, DY, T: Double;
begin
  DX := B.X - A.X; DY := B.Y - A.Y;
  T := DX * DX + DY * DY;
  if T < 1e-24 then Exit(Hypot(Q.X - A.X, Q.Y - A.Y));
  T := EnsureRange(((Q.X - A.X) * DX + (Q.Y - A.Y) * DY) / T, 0, 1);
  Result := Hypot(Q.X - (A.X + T * DX), Q.Y - (A.Y + T * DY));
end;

function DistanceToPolygon(const Q: TPoint2D; const P: TPolygon2D): Double;
var I, J: Integer;
begin
  Result := MaxDouble;
  J := High(P);
  for I := 0 to High(P) do begin
    Result := Min(Result, DistancePointSegment(Q, P[J], P[I]));
    J := I;
  end;
end;

procedure AddPt(var R: TPolygon2D; var N: Integer; X, Y: Double);
begin
  if N >= Length(R) then SetLength(R, Max(16, N * 2));
  R[N].X := X;
  R[N].Y := Y;
  Inc(N);
end;

function OffsetPolygon(const P: TPolygon2D; Delta: Double; Join: TJoinType;
  MiterLimit, ArcTolerance: Double): TPolygon2D;
var
  Src: TPolygon2D;
  Cnt, I, Prev, Next, N, Steps, K: Integer;
  NX, NY: array of Double;     // normais de cada aresta (para fora)
  D, Cross, Dot, A0, A1, Sweep, Step, MX, MY, L, Cos2, OrigArea, NewArea: Double;
begin
  SetLength(Result, 0);
  Src := SimplifyCollinear(P, 1e-9);
  Cnt := Length(Src);
  if Cnt < 3 then Exit;
  if Abs(Delta) < 1e-12 then Exit(Src);
  // Trabalha sempre em CCW: normal externa = (dy, -dx)
  if not PolygonIsCCW(Src) then Src := ReversePolygon(Src);
  OrigArea := PolygonArea(Src);
  SetLength(NX, Cnt);
  SetLength(NY, Cnt);
  for I := 0 to Cnt - 1 do begin
    Next := (I + 1) mod Cnt;
    D := Hypot(Src[Next].X - Src[I].X, Src[Next].Y - Src[I].Y);
    NX[I] := (Src[Next].Y - Src[I].Y) / D;
    NY[I] := -(Src[Next].X - Src[I].X) / D;
  end;
  N := 0;
  SetLength(Result, Cnt * 4);
  for I := 0 to Cnt - 1 do begin
    Prev := (I + Cnt - 1) mod Cnt;
    // aresta Prev termina no vertice I; aresta I comeca nele
    Cross := NX[Prev] * NY[I] - NY[Prev] * NX[I];
    Dot := NX[Prev] * NX[I] + NY[Prev] * NY[I];
    if Cross * Delta < 0 then begin
      // canto "concavo" na direcao do offset: interseccao das retas deslocadas
      Cos2 := 1 + Dot;
      if Cos2 < 1e-9 then
        AddPt(Result, N, Src[I].X + NX[I] * Delta, Src[I].Y + NY[I] * Delta)
      else begin
        MX := (NX[Prev] + NX[I]) / Cos2;
        MY := (NY[Prev] + NY[I]) / Cos2;
        AddPt(Result, N, Src[I].X + MX * Delta, Src[I].Y + MY * Delta);
      end;
    end else if Abs(Cross) < 1e-12 then
      AddPt(Result, N, Src[I].X + NX[I] * Delta, Src[I].Y + NY[I] * Delta)
    else
      case Join of
        jtMiter: begin
          Cos2 := 1 + Dot;
          L := Sqrt(2 / Max(Cos2, 1e-12)); // fator de miter
          if L <= MiterLimit then begin
            MX := (NX[Prev] + NX[I]) / Cos2;
            MY := (NY[Prev] + NY[I]) / Cos2;
            AddPt(Result, N, Src[I].X + MX * Delta, Src[I].Y + MY * Delta);
          end else begin
            AddPt(Result, N, Src[I].X + NX[Prev] * Delta, Src[I].Y + NY[Prev] * Delta);
            AddPt(Result, N, Src[I].X + NX[I] * Delta, Src[I].Y + NY[I] * Delta);
          end;
        end;
        jtSquare: begin
          AddPt(Result, N, Src[I].X + NX[Prev] * Delta, Src[I].Y + NY[Prev] * Delta);
          AddPt(Result, N, Src[I].X + NX[I] * Delta, Src[I].Y + NY[I] * Delta);
        end;
      else
        begin
          // arco centrado no vertice, de normal(Prev) ate normal(I)
          A0 := ArcTan2(NY[Prev] * Sign(Delta), NX[Prev] * Sign(Delta));
          A1 := ArcTan2(NY[I] * Sign(Delta), NX[I] * Sign(Delta));
          Sweep := A1 - A0;
          if Delta > 0 then begin
            while Sweep < 0 do Sweep := Sweep + 2 * Pi;
          end else begin
            while Sweep > 0 do Sweep := Sweep - 2 * Pi;
          end;
          if Abs(Delta) > ArcTolerance then
            Step := 2 * ArcCos(1 - ArcTolerance / Abs(Delta))
          else
            Step := Pi / 4;
          Steps := Max(1, Ceil(Abs(Sweep) / Max(Step, 1e-3)));
          for K := 0 to Steps do
            AddPt(Result, N, Src[I].X + Abs(Delta) * Cos(A0 + Sweep * K / Steps),
              Src[I].Y + Abs(Delta) * Sin(A0 + Sweep * K / Steps));
        end;
      end;
  end;
  SetLength(Result, N);
  Result := RemoveDuplicatePoints(Result);
  // Colapso: offset interno que inverte ou some
  NewArea := PolygonArea(Result);
  if (Length(Result) < 3) or (NewArea <= 1e-12) or ((Delta < 0) and (NewArea >= OrigArea)) then
    SetLength(Result, 0);
  // Verificacao de colapso: todo ponto de um offset interno deve estar
  // dentro do original e a pelo menos |Delta| de todas as arestas. Quando a
  // peca e mais estreita que 2*|Delta| as retas deslocadas se cruzam e o
  // poligono "vira do avesso" - isso e detectado aqui.
  // Vertices que violam a distancia estao em lacos "mortos" (ex.: arestas
  // curtas junto a cantos) e sao removidos; se sobrar pouco, colapsou.
  if (Delta < 0) and (Length(Result) > 0) then begin
    N := 0;
    for I := 0 to High(Result) do
      if PointInPolygon(Result[I], Src) and
        (DistanceToPolygon(Result[I], Src) >= Abs(Delta) * (1 - 1e-6) - 1e-6) then begin
        Result[N] := Result[I];
        Inc(N);
      end;
    SetLength(Result, N);
    if (N < 3) or (PolygonArea(Result) <= 1e-12) then SetLength(Result, 0);
  end;
end;

function SimplifyCollinear(const P: TPolygon2D; Eps: Double): TPolygon2D;
var I, N, Cnt, Prev, Next: Integer; Cross, L: Double; Keep: array of Boolean; Changed: Boolean;
begin
  Result := RemoveDuplicatePoints(P);
  repeat
    Changed := False;
    Cnt := Length(Result);
    if Cnt < 4 then Exit;
    SetLength(Keep, Cnt);
    for I := 0 to Cnt - 1 do begin
      Prev := (I + Cnt - 1) mod Cnt;
      Next := (I + 1) mod Cnt;
      Cross := (Result[I].X - Result[Prev].X) * (Result[Next].Y - Result[Prev].Y) -
        (Result[I].Y - Result[Prev].Y) * (Result[Next].X - Result[Prev].X);
      L := Hypot(Result[Next].X - Result[Prev].X, Result[Next].Y - Result[Prev].Y);
      // distancia do vertice a reta vizinha abaixo de Eps: colinear
      Keep[I] := (L < 1e-12) or (Abs(Cross) / L > Eps);
    end;
    N := 0;
    for I := 0 to Cnt - 1 do
      if Keep[I] or Changed then begin
        Result[N] := Result[I];
        Inc(N);
      end else
        Changed := True; // remove um por passada para manter vizinhancas validas
    SetLength(Result, N);
  until not Changed;
end;

function ClipPolylineToRegion(const Line: TPolygon2D; const Region: TPolygons2D): TPolygons2D;
var
  I, R, E, F, NT, NR, Cur: Integer;
  T: array of Double;
  A, B, C, D, M: TPoint2D;
  Den, TA, TB, Tmp: Double;
  Piece: TPolygon2D;
  PieceLen: Integer;

  procedure FlushPiece;
  begin
    if PieceLen >= 2 then begin
      SetLength(Piece, PieceLen);
      SetLength(Result, NR + 1);
      Result[NR] := Piece;
      Inc(NR);
    end;
    Piece := nil;
    PieceLen := 0;
  end;

  procedure PiecePoint(const Q: TPoint2D);
  begin
    if (PieceLen > 0) and (Abs(Piece[PieceLen - 1].X - Q.X) < 1e-12) and
      (Abs(Piece[PieceLen - 1].Y - Q.Y) < 1e-12) then Exit;
    if PieceLen >= Length(Piece) then SetLength(Piece, Max(8, PieceLen * 2));
    Piece[PieceLen] := Q;
    Inc(PieceLen);
  end;

begin
  SetLength(Result, 0);
  NR := 0;
  Piece := nil;
  PieceLen := 0;
  for I := 1 to High(Line) do begin
    A := Line[I - 1];
    B := Line[I];
    // parametros de interseccao do segmento AB com todas as arestas
    SetLength(T, 2);
    T[0] := 0; T[1] := 1;
    NT := 2;
    for R := 0 to High(Region) do begin
      F := High(Region[R]);
      for E := 0 to High(Region[R]) do begin
        C := Region[R][F];
        D := Region[R][E];
        Den := (B.X - A.X) * (D.Y - C.Y) - (B.Y - A.Y) * (D.X - C.X);
        if Abs(Den) > 1e-15 then begin
          TA := ((C.X - A.X) * (D.Y - C.Y) - (C.Y - A.Y) * (D.X - C.X)) / Den;
          TB := ((C.X - A.X) * (B.Y - A.Y) - (C.Y - A.Y) * (B.X - A.X)) / Den;
          if (TA > 1e-12) and (TA < 1 - 1e-12) and (TB >= 0) and (TB <= 1) then begin
            SetLength(T, NT + 1);
            T[NT] := TA;
            Inc(NT);
          end;
        end;
        F := E;
      end;
    end;
    // ordena (insercao: poucos cortes por segmento)
    for E := 1 to NT - 1 do begin
      Tmp := T[E];
      Cur := E - 1;
      while (Cur >= 0) and (T[Cur] > Tmp) do begin T[Cur + 1] := T[Cur]; Dec(Cur); end;
      T[Cur + 1] := Tmp;
    end;
    for E := 0 to NT - 2 do begin
      if T[E + 1] - T[E] < 1e-12 then Continue;
      M := Pt(A.X + (B.X - A.X) * (T[E] + T[E + 1]) / 2, A.Y + (B.Y - A.Y) * (T[E] + T[E + 1]) / 2);
      if PointInPolygons(M, Region) then begin
        PiecePoint(Pt(A.X + (B.X - A.X) * T[E], A.Y + (B.Y - A.Y) * T[E]));
        PiecePoint(Pt(A.X + (B.X - A.X) * T[E + 1], A.Y + (B.Y - A.Y) * T[E + 1]));
      end else
        FlushPiece;
    end;
  end;
  FlushPiece;
end;

function ChainSegments(const Segs: TSegments2D; Tol: Double): TPolygons2D;
var
  Used: array of Boolean;
  I, J, Remaining, N, Best: Integer;
  Poly: TPolygon2D;
  Tail: TPoint2D;
  Found, Reverse: Boolean;
  Count: Integer;

  function Near(const P, Q: TPoint2D): Boolean;
  begin
    Result := (Abs(P.X - Q.X) <= Tol) and (Abs(P.Y - Q.Y) <= Tol);
  end;

begin
  SetLength(Result, 0);
  Count := 0;
  SetLength(Used, Length(Segs));
  Remaining := Length(Segs);
  for I := 0 to High(Segs) do
    if Near(Segs[I].A, Segs[I].B) then begin Used[I] := True; Dec(Remaining); end;
  while Remaining > 0 do begin
    I := 0;
    while Used[I] do Inc(I);
    Used[I] := True;
    Dec(Remaining);
    SetLength(Poly, 2);
    Poly[0] := Segs[I].A;
    Poly[1] := Segs[I].B;
    N := 2;
    repeat
      Tail := Poly[N - 1];
      Found := False;
      Best := -1;
      Reverse := False;
      for J := 0 to High(Segs) do begin
        if Used[J] then Continue;
        if Near(Segs[J].A, Tail) then begin Best := J; Reverse := False; Found := True; Break; end;
        if Near(Segs[J].B, Tail) then begin Best := J; Reverse := True; Found := True; Break; end;
      end;
      if Found then begin
        Used[Best] := True;
        Dec(Remaining);
        SetLength(Poly, N + 1);
        if Reverse then Poly[N] := Segs[Best].A else Poly[N] := Segs[Best].B;
        Inc(N);
      end;
    until (not Found) or Near(Poly[N - 1], Poly[0]);
    if Near(Poly[N - 1], Poly[0]) then Dec(N); // fecha o laco
    SetLength(Poly, N);
    if N >= 3 then begin
      SetLength(Result, Count + 1);
      Result[Count] := Poly;
      Inc(Count);
    end;
  end;
end;

end.
