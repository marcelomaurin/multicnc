unit laserpcb_geom;

{ Tipos geometricos basicos do LaserPCB (milimetros, Y para cima).

  - TLPPoint / TLPPath / TLPPaths: pontos e polilinhas.
  - TLPRect: caixa envolvente.
  - TLPMatrix: transformacao afim 2D (espelho, rotacao, escala, translacao).
  - utilitarios: comprimento, area com sinal, simplificacao Douglas-Peucker,
    ordenacao de caminhos por vizinho mais proximo. }

{$mode objfpc}{$H+}

interface

uses
  Math;

type
  TLPPoint = record
    X, Y: Double;
  end;

  TLPPath = array of TLPPoint;
  TLPPaths = array of TLPPath;

  TLPRect = record
    MinX, MinY, MaxX, MaxY: Double;
    Valid: Boolean;
  end;

  { afim: X' = A*X + B*Y + C ; Y' = D*X + E*Y + F }
  TLPMatrix = record
    A, B, C, D, E, F: Double;
  end;

function LPPoint(X, Y: Double): TLPPoint; inline;
function LPDist(const P, Q: TLPPoint): Double; inline;

{ caixas }
function LPEmptyRect: TLPRect;
procedure LPRectInclude(var R: TLPRect; X, Y: Double);
procedure LPRectIncludeRect(var R: TLPRect; const S: TLPRect);
procedure LPRectInflate(var R: TLPRect; D: Double);
function LPRectWidth(const R: TLPRect): Double;
function LPRectHeight(const R: TLPRect): Double;
function LPPathsBounds(const P: TLPPaths): TLPRect;

{ caminhos }
procedure LPAddPoint(var P: TLPPath; X, Y: Double);
procedure LPAddPath(var Paths: TLPPaths; const P: TLPPath);
procedure LPAddPaths(var Paths: TLPPaths; const More: TLPPaths);
function LPPathLength(const P: TLPPath): Double;
function LPPathsLength(const P: TLPPaths): Double;
function LPSignedArea(const P: TLPPath): Double;
function LPIsClosed(const P: TLPPath; Tol: Double = 1e-6): Boolean;
function LPSimplify(const P: TLPPath; Tol: Double): TLPPath;
function LPReversed(const P: TLPPath): TLPPath;
{ ordena por vizinho mais proximo a partir de (StartX, StartY); caminhos
  abertos podem ser invertidos; fechados podem comecar no vertice mais
  proximo (rotacao do ciclo) }
function LPOrderPaths(const P: TLPPaths; StartX, StartY: Double): TLPPaths;
{ circulo/arco aproximado por segmentos com erro de corda <= Tol }
function LPArcSegments(R, SweepRad, Tol: Double): Integer;
function LPCircle(CX, CY, R, Tol: Double): TLPPath;

{ matrizes }
function LPIdentity: TLPMatrix;
function LPTranslate(DX, DY: Double): TLPMatrix;
function LPScale(SX, SY: Double): TLPMatrix;
function LPRotate(Deg: Double): TLPMatrix;
{ M2 aplicada depois de M1 }
function LPMul(const M1, M2: TLPMatrix): TLPMatrix;
function LPApply(const M: TLPMatrix; const P: TLPPoint): TLPPoint;
function LPApplyPaths(const M: TLPMatrix; const P: TLPPaths): TLPPaths;
function LPIsMirror(const M: TLPMatrix): Boolean;

implementation

function LPPoint(X, Y: Double): TLPPoint;
begin
  Result.X := X;
  Result.Y := Y;
end;

function LPDist(const P, Q: TLPPoint): Double;
begin
  Result := Hypot(P.X - Q.X, P.Y - Q.Y);
end;

function LPEmptyRect: TLPRect;
begin
  Result.MinX := 0; Result.MinY := 0; Result.MaxX := 0; Result.MaxY := 0;
  Result.Valid := False;
end;

procedure LPRectInclude(var R: TLPRect; X, Y: Double);
begin
  if not R.Valid then
  begin
    R.MinX := X; R.MaxX := X; R.MinY := Y; R.MaxY := Y;
    R.Valid := True;
    Exit;
  end;
  if X < R.MinX then R.MinX := X;
  if X > R.MaxX then R.MaxX := X;
  if Y < R.MinY then R.MinY := Y;
  if Y > R.MaxY then R.MaxY := Y;
end;

procedure LPRectIncludeRect(var R: TLPRect; const S: TLPRect);
begin
  if not S.Valid then Exit;
  LPRectInclude(R, S.MinX, S.MinY);
  LPRectInclude(R, S.MaxX, S.MaxY);
end;

procedure LPRectInflate(var R: TLPRect; D: Double);
begin
  if not R.Valid then Exit;
  R.MinX := R.MinX - D; R.MinY := R.MinY - D;
  R.MaxX := R.MaxX + D; R.MaxY := R.MaxY + D;
end;

function LPRectWidth(const R: TLPRect): Double;
begin
  if R.Valid then Result := R.MaxX - R.MinX else Result := 0;
end;

function LPRectHeight(const R: TLPRect): Double;
begin
  if R.Valid then Result := R.MaxY - R.MinY else Result := 0;
end;

function LPPathsBounds(const P: TLPPaths): TLPRect;
var
  I, J: Integer;
begin
  Result := LPEmptyRect;
  for I := 0 to High(P) do
    for J := 0 to High(P[I]) do
      LPRectInclude(Result, P[I][J].X, P[I][J].Y);
end;

procedure LPAddPoint(var P: TLPPath; X, Y: Double);
var
  N: Integer;
begin
  N := Length(P);
  SetLength(P, N + 1);
  P[N].X := X;
  P[N].Y := Y;
end;

procedure LPAddPath(var Paths: TLPPaths; const P: TLPPath);
var
  N: Integer;
begin
  if Length(P) = 0 then Exit;
  N := Length(Paths);
  SetLength(Paths, N + 1);
  Paths[N] := P;
end;

procedure LPAddPaths(var Paths: TLPPaths; const More: TLPPaths);
var
  I, N: Integer;
begin
  N := Length(Paths);
  SetLength(Paths, N + Length(More));
  for I := 0 to High(More) do
    Paths[N + I] := More[I];
end;

function LPPathLength(const P: TLPPath): Double;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to High(P) do
    Result := Result + LPDist(P[I - 1], P[I]);
end;

function LPPathsLength(const P: TLPPaths): Double;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(P) do
    Result := Result + LPPathLength(P[I]);
end;

function LPSignedArea(const P: TLPPath): Double;
var
  I, J: Integer;
begin
  Result := 0;
  if Length(P) < 3 then Exit;
  J := High(P);
  for I := 0 to High(P) do
  begin
    Result := Result + (P[J].X * P[I].Y - P[I].X * P[J].Y);
    J := I;
  end;
  Result := Result / 2;
end;

function LPIsClosed(const P: TLPPath; Tol: Double): Boolean;
begin
  Result := (Length(P) > 2) and (LPDist(P[0], P[High(P)]) <= Tol);
end;

function SegDist(const P, A, B: TLPPoint): Double;
var
  DX, DY, T, L2: Double;
begin
  DX := B.X - A.X;
  DY := B.Y - A.Y;
  L2 := DX * DX + DY * DY;
  if L2 < 1e-18 then Exit(LPDist(P, A));
  T := EnsureRange(((P.X - A.X) * DX + (P.Y - A.Y) * DY) / L2, 0, 1);
  Result := Hypot(P.X - (A.X + T * DX), P.Y - (A.Y + T * DY));
end;

function LPSimplify(const P: TLPPath; Tol: Double): TLPPath;
var
  Keep: array of Boolean;
  Stack: array of Integer;
  SP, I, A, B, Idx, N: Integer;
  D, DMax: Double;
begin
  N := Length(P);
  if (N < 3) or (Tol <= 0) then Exit(Copy(P));
  SetLength(Keep, N);
  Keep[0] := True;
  Keep[N - 1] := True;
  SetLength(Stack, 2 * N + 2);
  SP := 0;
  Stack[SP] := 0; Stack[SP + 1] := N - 1; Inc(SP, 2);
  while SP > 0 do
  begin
    Dec(SP, 2);
    A := Stack[SP];
    B := Stack[SP + 1];
    DMax := -1;
    Idx := -1;
    for I := A + 1 to B - 1 do
    begin
      D := SegDist(P[I], P[A], P[B]);
      if D > DMax then
      begin
        DMax := D;
        Idx := I;
      end;
    end;
    if (Idx > 0) and (DMax > Tol) then
    begin
      Keep[Idx] := True;
      Stack[SP] := A; Stack[SP + 1] := Idx; Inc(SP, 2);
      Stack[SP] := Idx; Stack[SP + 1] := B; Inc(SP, 2);
    end;
  end;
  Result := nil;
  for I := 0 to N - 1 do
    if Keep[I] then LPAddPoint(Result, P[I].X, P[I].Y);
end;

function LPReversed(const P: TLPPath): TLPPath;
var
  I, N: Integer;
begin
  N := Length(P);
  SetLength(Result, N);
  for I := 0 to N - 1 do
    Result[I] := P[N - 1 - I];
end;

{ fechado: gira o ciclo para comecar no vertice K }
function RotateClosed(const P: TLPPath; K: Integer): TLPPath;
var
  I, N, M: Integer;
begin
  N := Length(P);
  M := N - 1; { ultimo ponto repete o primeiro }
  SetLength(Result, N);
  for I := 0 to M - 1 do
    Result[I] := P[(K + I) mod M];
  Result[M] := Result[0];
end;

function LPOrderPaths(const P: TLPPaths; StartX, StartY: Double): TLPPaths;
var
  Used: array of Boolean;
  I, J, K, Best, BestK, N: Integer;
  BestRev: Boolean;
  Cur: TLPPoint;
  D, BestD: Double;
  Q: TLPPath;
begin
  N := Length(P);
  SetLength(Result, 0);
  SetLength(Used, N);
  Cur := LPPoint(StartX, StartY);
  for K := 0 to N - 1 do
  begin
    Best := -1;
    BestD := MaxDouble;
    BestRev := False;
    BestK := 0;
    for I := 0 to N - 1 do
    begin
      if Used[I] or (Length(P[I]) = 0) then Continue;
      if LPIsClosed(P[I]) then
      begin
        for J := 0 to High(P[I]) - 1 do
        begin
          D := Sqr(P[I][J].X - Cur.X) + Sqr(P[I][J].Y - Cur.Y);
          if D < BestD then
          begin
            BestD := D; Best := I; BestRev := False; BestK := J;
          end;
        end;
      end
      else
      begin
        D := Sqr(P[I][0].X - Cur.X) + Sqr(P[I][0].Y - Cur.Y);
        if D < BestD then
        begin
          BestD := D; Best := I; BestRev := False; BestK := 0;
        end;
        D := Sqr(P[I][High(P[I])].X - Cur.X) + Sqr(P[I][High(P[I])].Y - Cur.Y);
        if D < BestD then
        begin
          BestD := D; Best := I; BestRev := True; BestK := 0;
        end;
      end;
    end;
    if Best < 0 then Break;
    Used[Best] := True;
    if LPIsClosed(P[Best]) then
      Q := RotateClosed(P[Best], BestK)
    else if BestRev then
      Q := LPReversed(P[Best])
    else
      Q := Copy(P[Best]);
    LPAddPath(Result, Q);
    Cur := Q[High(Q)];
  end;
end;

function LPArcSegments(R, SweepRad, Tol: Double): Integer;
var
  Step: Double;
begin
  if (R <= Tol) or (Tol <= 0) then Exit(Max(4, Ceil(Abs(SweepRad) / (Pi / 4))));
  Step := 2 * ArcCos(1 - Tol / R);
  if Step <= 1e-6 then Step := 1e-6;
  Result := EnsureRange(Ceil(Abs(SweepRad) / Step), 4, 2000);
end;

function LPCircle(CX, CY, R, Tol: Double): TLPPath;
var
  I, N: Integer;
  A: Double;
begin
  N := LPArcSegments(R, 2 * Pi, Tol);
  SetLength(Result, N + 1);
  for I := 0 to N do
  begin
    A := 2 * Pi * I / N;
    Result[I].X := CX + R * Cos(A);
    Result[I].Y := CY + R * Sin(A);
  end;
end;

function LPIdentity: TLPMatrix;
begin
  Result.A := 1; Result.B := 0; Result.C := 0;
  Result.D := 0; Result.E := 1; Result.F := 0;
end;

function LPTranslate(DX, DY: Double): TLPMatrix;
begin
  Result := LPIdentity;
  Result.C := DX;
  Result.F := DY;
end;

function LPScale(SX, SY: Double): TLPMatrix;
begin
  Result := LPIdentity;
  Result.A := SX;
  Result.E := SY;
end;

function LPRotate(Deg: Double): TLPMatrix;
var
  R: Double;
begin
  R := DegToRad(Deg);
  Result := LPIdentity;
  Result.A := Cos(R); Result.B := -Sin(R);
  Result.D := Sin(R); Result.E := Cos(R);
end;

function LPMul(const M1, M2: TLPMatrix): TLPMatrix;
begin
  { P' = M2 * (M1 * P) }
  Result.A := M2.A * M1.A + M2.B * M1.D;
  Result.B := M2.A * M1.B + M2.B * M1.E;
  Result.C := M2.A * M1.C + M2.B * M1.F + M2.C;
  Result.D := M2.D * M1.A + M2.E * M1.D;
  Result.E := M2.D * M1.B + M2.E * M1.E;
  Result.F := M2.D * M1.C + M2.E * M1.F + M2.F;
end;

function LPApply(const M: TLPMatrix; const P: TLPPoint): TLPPoint;
begin
  Result.X := M.A * P.X + M.B * P.Y + M.C;
  Result.Y := M.D * P.X + M.E * P.Y + M.F;
end;

function LPApplyPaths(const M: TLPMatrix; const P: TLPPaths): TLPPaths;
var
  I, J: Integer;
begin
  SetLength(Result, Length(P));
  for I := 0 to High(P) do
  begin
    SetLength(Result[I], Length(P[I]));
    for J := 0 to High(P[I]) do
      Result[I][J] := LPApply(M, P[I][J]);
  end;
end;

function LPIsMirror(const M: TLPMatrix): Boolean;
begin
  Result := (M.A * M.E - M.B * M.D) < 0;
end;

end.
