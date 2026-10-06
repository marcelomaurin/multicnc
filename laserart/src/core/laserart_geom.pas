unit laserart_geom;

{ Geometria do LaserArt: contorno dos objetos em coordenadas do mundo,
  caixas envolventes, preenchimento por varredura (hatch), simplificacao e
  ordenacao de percurso. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, laserart_model;

type
  TLABox = record
    X1, Y1, X2, Y2: Double;
    Valid: Boolean;
  end;

  TLASegment = record
    A, B: TLAPoint;
  end;
  TLASegments = array of TLASegment;
  TLAPoints = array of TLAPoint;

{ geometria propria (sem posicao/rotacao), em mm, 0..W x 0..H }
function ShapeLocalPaths(S: TLAShape): TLAPaths;
{ geometria no mundo, com espelhamento, rotacao e posicao }
function ShapeWorldPaths(S: TLAShape): TLAPaths;
function ShapeCorners(S: TLAShape): TLAPoints;  { 4 cantos no mundo }
function ShapeCenter(S: TLAShape): TLAPoint;
function ShapeBox(S: TLAShape): TLABox;
function PathsBox(const P: TLAPaths): TLABox;
function UnionBox(const A, B: TLABox): TLABox;
function EmptyBox: TLABox;
function WorldToShapeLocal(S: TLAShape; const P: TLAPoint): TLAPoint;

{ preenchimento par-impar por linhas horizontais espacadas de Interval }
function HatchPaths(const P: TLAPaths; Interval: Double): TLASegments;
{ Douglas-Peucker }
function SimplifyPath(const P: TLAPath; Tolerance: Double): TLAPath;
{ ordena caminhos pelo vizinho mais proximo; caminhos abertos podem inverter }
procedure OrderPaths(var P: TLAPaths; StartX, StartY: Double);
function PathLength(const P: TLAPath): Double;
function PointInPaths(const P: TLAPaths; X, Y: Double): Boolean;
function DistanceToPaths(const P: TLAPaths; X, Y: Double): Double;
function NormalizePaths(var P: TLAPaths; out W, H: Double): Boolean;
function RotatePoint(const P, C: TLAPoint; AngleDeg: Double): TLAPoint;

implementation

function EmptyBox: TLABox;
begin
  Result.X1 := 0; Result.Y1 := 0; Result.X2 := 0; Result.Y2 := 0;
  Result.Valid := False;
end;

function UnionBox(const A, B: TLABox): TLABox;
begin
  if not A.Valid then Exit(B);
  if not B.Valid then Exit(A);
  Result.X1 := Min(A.X1, B.X1); Result.Y1 := Min(A.Y1, B.Y1);
  Result.X2 := Max(A.X2, B.X2); Result.Y2 := Max(A.Y2, B.Y2);
  Result.Valid := True;
end;

function PathsBox(const P: TLAPaths): TLABox;
var
  I, J: Integer;
begin
  Result := EmptyBox;
  for I := 0 to High(P) do
    for J := 0 to High(P[I].Pts) do
      with P[I].Pts[J] do
        if not Result.Valid then
        begin
          Result.X1 := X; Result.X2 := X; Result.Y1 := Y; Result.Y2 := Y;
          Result.Valid := True;
        end
        else
        begin
          Result.X1 := Min(Result.X1, X); Result.X2 := Max(Result.X2, X);
          Result.Y1 := Min(Result.Y1, Y); Result.Y2 := Max(Result.Y2, Y);
        end;
end;

function RotatePoint(const P, C: TLAPoint; AngleDeg: Double): TLAPoint;
var
  S, CS, DX, DY: Double;
begin
  if AngleDeg = 0 then Exit(P);
  SinCos(DegToRad(AngleDeg), S, CS);
  DX := P.X - C.X; DY := P.Y - C.Y;
  Result.X := C.X + DX * CS - DY * S;
  Result.Y := C.Y + DX * S + DY * CS;
end;

function NormalizePaths(var P: TLAPaths; out W, H: Double): Boolean;
var
  B: TLABox;
  I, J: Integer;
begin
  B := PathsBox(P);
  Result := B.Valid;
  W := 0; H := 0;
  if not Result then Exit;
  for I := 0 to High(P) do
    for J := 0 to High(P[I].Pts) do
    begin
      P[I].Pts[J].X := P[I].Pts[J].X - B.X1;
      P[I].Pts[J].Y := P[I].Pts[J].Y - B.Y1;
    end;
  W := B.X2 - B.X1;
  H := B.Y2 - B.Y1;
end;

procedure AddClosed(var R: TLAPaths; const Pts: array of TLAPoint);
var
  N, I: Integer;
begin
  N := Length(R);
  SetLength(R, N + 1);
  SetLength(R[N].Pts, Length(Pts));
  for I := 0 to High(Pts) do
    R[N].Pts[I] := Pts[I];
  R[N].Closed := True;
end;

function ShapeLocalPaths(S: TLAShape): TLAPaths;
var
  I, J, N, Seg: Integer;
  A, Rad, SX, SY: Double;
  Pts: array of TLAPoint;
begin
  SetLength(Result, 0);
  case S.Kind of
    skRect, skImage:
      begin
        Rad := Min(S.CornerRadius, Min(S.W, S.H) / 2);
        if (S.Kind = skImage) or (Rad <= 0.01) then
          AddClosed(Result, [LAPoint(0, 0), LAPoint(S.W, 0), LAPoint(S.W, S.H), LAPoint(0, S.H)])
        else
        begin
          Seg := 8;
          SetLength(Pts, 4 * (Seg + 1));
          N := 0;
          for I := 0 to 3 do
            for J := 0 to Seg do
            begin
              A := DegToRad(I * 90 + 180 + 90 * J / Seg);
              case I of
                0: Pts[N] := LAPoint(Rad + Rad * Cos(A), Rad + Rad * Sin(A));
                1: Pts[N] := LAPoint(S.W - Rad + Rad * Cos(A), Rad + Rad * Sin(A));
                2: Pts[N] := LAPoint(S.W - Rad + Rad * Cos(A), S.H - Rad + Rad * Sin(A));
                3: Pts[N] := LAPoint(Rad + Rad * Cos(A), S.H - Rad + Rad * Sin(A));
              end;
              Inc(N);
            end;
          AddClosed(Result, Pts);
        end;
      end;
    skEllipse:
      begin
        N := Max(48, Min(360, Round(Pi * (S.W + S.H) / 1.5)));
        SetLength(Pts, N);
        for I := 0 to N - 1 do
        begin
          A := 2 * Pi * I / N;
          Pts[I] := LAPoint(S.W / 2 + S.W / 2 * Cos(A), S.H / 2 + S.H / 2 * Sin(A));
        end;
        AddClosed(Result, Pts);
      end;
    skPolygon:
      begin
        N := EnsureRange(S.Sides, 3, 64);
        SetLength(Pts, N);
        for I := 0 to N - 1 do
        begin
          A := DegToRad(90 + 360 * I / N);
          Pts[I] := LAPoint(S.W / 2 + S.W / 2 * Cos(A), S.H / 2 + S.H / 2 * Sin(A));
        end;
        AddClosed(Result, Pts);
      end;
    skPath, skText:
      begin
        if (S.LocalW <= 0) and (S.LocalH <= 0) then Exit;
        if S.LocalW > 0 then SX := S.W / S.LocalW else SX := 1;
        if S.LocalH > 0 then SY := S.H / S.LocalH else SY := 1;
        SetLength(Result, Length(S.Local));
        for I := 0 to High(S.Local) do
        begin
          Result[I].Closed := S.Local[I].Closed;
          SetLength(Result[I].Pts, Length(S.Local[I].Pts));
          for J := 0 to High(S.Local[I].Pts) do
          begin
            Result[I].Pts[J].X := S.Local[I].Pts[J].X * SX;
            Result[I].Pts[J].Y := S.Local[I].Pts[J].Y * SY;
          end;
        end;
      end;
  end;
end;

function ShapeCenter(S: TLAShape): TLAPoint;
begin
  Result := LAPoint(S.X + S.W / 2, S.Y + S.H / 2);
end;

function LocalToWorld(S: TLAShape; const P: TLAPoint): TLAPoint; inline;
var
  Q: TLAPoint;
begin
  Q := P;
  if S.MirrorX then Q.X := S.W - Q.X;
  if S.MirrorY then Q.Y := S.H - Q.Y;
  Q.X := Q.X + S.X;
  Q.Y := Q.Y + S.Y;
  Result := RotatePoint(Q, ShapeCenter(S), S.Angle);
end;

function WorldToShapeLocal(S: TLAShape; const P: TLAPoint): TLAPoint;
begin
  Result := RotatePoint(P, ShapeCenter(S), -S.Angle);
  Result.X := Result.X - S.X;
  Result.Y := Result.Y - S.Y;
  if S.MirrorX then Result.X := S.W - Result.X;
  if S.MirrorY then Result.Y := S.H - Result.Y;
end;

function ShapeWorldPaths(S: TLAShape): TLAPaths;
var
  I, J: Integer;
begin
  Result := ShapeLocalPaths(S);
  for I := 0 to High(Result) do
    for J := 0 to High(Result[I].Pts) do
      Result[I].Pts[J] := LocalToWorld(S, Result[I].Pts[J]);
end;

function ShapeCorners(S: TLAShape): TLAPoints;
begin
  SetLength(Result, 4);
  Result[0] := RotatePoint(LAPoint(S.X, S.Y), ShapeCenter(S), S.Angle);
  Result[1] := RotatePoint(LAPoint(S.X + S.W, S.Y), ShapeCenter(S), S.Angle);
  Result[2] := RotatePoint(LAPoint(S.X + S.W, S.Y + S.H), ShapeCenter(S), S.Angle);
  Result[3] := RotatePoint(LAPoint(S.X, S.Y + S.H), ShapeCenter(S), S.Angle);
end;

function ShapeBox(S: TLAShape): TLABox;
var
  C: TLAPoints;
  I: Integer;
begin
  if S.Angle = 0 then
  begin
    Result.X1 := S.X; Result.Y1 := S.Y;
    Result.X2 := S.X + S.W; Result.Y2 := S.Y + S.H;
    Result.Valid := True;
    Exit;
  end;
  C := ShapeCorners(S);
  Result.X1 := C[0].X; Result.X2 := C[0].X; Result.Y1 := C[0].Y; Result.Y2 := C[0].Y;
  for I := 1 to 3 do
  begin
    Result.X1 := Min(Result.X1, C[I].X); Result.X2 := Max(Result.X2, C[I].X);
    Result.Y1 := Min(Result.Y1, C[I].Y); Result.Y2 := Max(Result.Y2, C[I].Y);
  end;
  Result.Valid := True;
end;

{ ---------------------------------------------------------------------------- }

function HatchPaths(const P: TLAPaths; Interval: Double): TLASegments;
var
  B: TLABox;
  Y: Double;
  I, J, K, N, Row: Integer;
  Xs: array of Double;
  A, C: TLAPoint;
  T, Tmp: Double;
  Count: Integer;
begin
  SetLength(Result, 0);
  if Interval <= 0.001 then Exit;
  B := PathsBox(P);
  if not B.Valid then Exit;
  Count := 0;
  Row := 0;
  Y := B.Y1 + Interval / 2;
  SetLength(Xs, 64);
  while Y < B.Y2 do
  begin
    N := 0;
    for I := 0 to High(P) do
    begin
      if Length(P[I].Pts) < 2 then Continue;
      for J := 0 to High(P[I].Pts) do
      begin
        A := P[I].Pts[J];
        if J < High(P[I].Pts) then
          C := P[I].Pts[J + 1]
        else
          C := P[I].Pts[0];       { contorno sempre fechado para preencher }
        if (A.Y = C.Y) then Continue;
        if ((Y >= A.Y) and (Y < C.Y)) or ((Y >= C.Y) and (Y < A.Y)) then
        begin
          T := (Y - A.Y) / (C.Y - A.Y);
          if N >= Length(Xs) then SetLength(Xs, N * 2);
          Xs[N] := A.X + T * (C.X - A.X);
          Inc(N);
        end;
      end;
    end;
    { ordena as intersecoes }
    for I := 1 to N - 1 do
    begin
      Tmp := Xs[I];
      K := I - 1;
      while (K >= 0) and (Xs[K] > Tmp) do
      begin
        Xs[K + 1] := Xs[K];
        Dec(K);
      end;
      Xs[K + 1] := Tmp;
    end;
    { pares par-impar; linhas alternam o sentido (bidirecional) }
    I := 0;
    if Odd(Row) then
    begin
      I := (N div 2) * 2 - 2;
      while I >= 0 do
      begin
        if Xs[I + 1] - Xs[I] > 0.001 then
        begin
          if Count >= Length(Result) then SetLength(Result, Max(64, Count * 2));
          Result[Count].A := LAPoint(Xs[I + 1], Y);
          Result[Count].B := LAPoint(Xs[I], Y);
          Inc(Count);
        end;
        Dec(I, 2);
      end;
    end
    else
      while I + 1 < N do
      begin
        if Xs[I + 1] - Xs[I] > 0.001 then
        begin
          if Count >= Length(Result) then SetLength(Result, Max(64, Count * 2));
          Result[Count].A := LAPoint(Xs[I], Y);
          Result[Count].B := LAPoint(Xs[I + 1], Y);
          Inc(Count);
        end;
        Inc(I, 2);
      end;
    Y := Y + Interval;
    Inc(Row);
  end;
  SetLength(Result, Count);
end;

{ ---------------------------------------------------------------------------- }

function PerpDist(const P, A, B: TLAPoint): Double;
var
  DX, DY, L: Double;
begin
  DX := B.X - A.X; DY := B.Y - A.Y;
  L := Hypot(DX, DY);
  if L < 1e-12 then
    Result := Hypot(P.X - A.X, P.Y - A.Y)
  else
    Result := Abs(DX * (A.Y - P.Y) - (A.X - P.X) * DY) / L;
end;

function SimplifyPath(const P: TLAPath; Tolerance: Double): TLAPath;
var
  Keep: array of Boolean;
  Stack: array of Integer;
  SP, A, B, I, Idx, N: Integer;
  DMax, D: Double;
begin
  N := Length(P.Pts);
  Result.Closed := P.Closed;
  if N <= 3 then
  begin
    Result.Pts := Copy(P.Pts);
    Exit;
  end;
  SetLength(Keep, N);
  Keep[0] := True;
  Keep[N - 1] := True;
  SetLength(Stack, N * 2 + 2);
  SP := 0;
  Stack[SP] := 0; Stack[SP + 1] := N - 1; Inc(SP, 2);
  while SP > 0 do
  begin
    Dec(SP, 2);
    A := Stack[SP]; B := Stack[SP + 1];
    DMax := 0; Idx := -1;
    for I := A + 1 to B - 1 do
    begin
      D := PerpDist(P.Pts[I], P.Pts[A], P.Pts[B]);
      if D > DMax then begin DMax := D; Idx := I; end;
    end;
    if (Idx > 0) and (DMax > Tolerance) then
    begin
      Keep[Idx] := True;
      Stack[SP] := A; Stack[SP + 1] := Idx; Inc(SP, 2);
      Stack[SP] := Idx; Stack[SP + 1] := B; Inc(SP, 2);
    end;
  end;
  SetLength(Result.Pts, N);
  Idx := 0;
  for I := 0 to N - 1 do
    if Keep[I] then
    begin
      Result.Pts[Idx] := P.Pts[I];
      Inc(Idx);
    end;
  SetLength(Result.Pts, Idx);
end;

function PathLength(const P: TLAPath): Double;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to High(P.Pts) do
    Result := Result + Hypot(P.Pts[I].X - P.Pts[I - 1].X, P.Pts[I].Y - P.Pts[I - 1].Y);
  if P.Closed and (Length(P.Pts) > 2) then
    Result := Result + Hypot(P.Pts[0].X - P.Pts[High(P.Pts)].X, P.Pts[0].Y - P.Pts[High(P.Pts)].Y);
end;

procedure ReversePath(var P: TLAPath);
var
  I, N: Integer;
  T: TLAPoint;
begin
  N := Length(P.Pts);
  for I := 0 to N div 2 - 1 do
  begin
    T := P.Pts[I];
    P.Pts[I] := P.Pts[N - 1 - I];
    P.Pts[N - 1 - I] := T;
  end;
end;

procedure OrderPaths(var P: TLAPaths; StartX, StartY: Double);
var
  Done: array of Boolean;
  R: TLAPaths;
  I, K, Best, N: Integer;
  BestD, D, CX, CY: Double;
  BestRev: Boolean;
begin
  N := Length(P);
  if N < 2 then Exit;
  SetLength(Done, N);
  SetLength(R, N);
  CX := StartX; CY := StartY;
  for K := 0 to N - 1 do
  begin
    Best := -1; BestD := MaxDouble; BestRev := False;
    for I := 0 to N - 1 do
    begin
      if Done[I] or (Length(P[I].Pts) = 0) then Continue;
      D := Sqr(P[I].Pts[0].X - CX) + Sqr(P[I].Pts[0].Y - CY);
      if D < BestD then begin BestD := D; Best := I; BestRev := False; end;
      if not P[I].Closed then
      begin
        D := Sqr(P[I].Pts[High(P[I].Pts)].X - CX) + Sqr(P[I].Pts[High(P[I].Pts)].Y - CY);
        if D < BestD then begin BestD := D; Best := I; BestRev := True; end;
      end;
    end;
    if Best < 0 then
    begin
      for I := 0 to N - 1 do
        if not Done[I] then begin Best := I; Break; end;
    end;
    Done[Best] := True;
    R[K] := P[Best];
    R[K].Pts := Copy(P[Best].Pts);
    if BestRev then ReversePath(R[K]);
    if Length(R[K].Pts) > 0 then
    begin
      if R[K].Closed then
      begin
        CX := R[K].Pts[0].X; CY := R[K].Pts[0].Y;
      end
      else
      begin
        CX := R[K].Pts[High(R[K].Pts)].X; CY := R[K].Pts[High(R[K].Pts)].Y;
      end;
    end;
  end;
  P := R;
end;

function PointInPaths(const P: TLAPaths; X, Y: Double): Boolean;
var
  I, J, K: Integer;
  A, B: TLAPoint;
begin
  Result := False;
  for I := 0 to High(P) do
  begin
    K := High(P[I].Pts);
    for J := 0 to High(P[I].Pts) do
    begin
      A := P[I].Pts[J];
      B := P[I].Pts[K];
      if ((A.Y > Y) <> (B.Y > Y)) and
         (X < (B.X - A.X) * (Y - A.Y) / (B.Y - A.Y) + A.X) then
        Result := not Result;
      K := J;
    end;
  end;
end;

function SegDist(X, Y: Double; const A, B: TLAPoint): Double;
var
  DX, DY, T: Double;
begin
  DX := B.X - A.X; DY := B.Y - A.Y;
  if (DX = 0) and (DY = 0) then Exit(Hypot(X - A.X, Y - A.Y));
  T := EnsureRange(((X - A.X) * DX + (Y - A.Y) * DY) / (DX * DX + DY * DY), 0, 1);
  Result := Hypot(X - (A.X + T * DX), Y - (A.Y + T * DY));
end;

function DistanceToPaths(const P: TLAPaths; X, Y: Double): Double;
var
  I, J: Integer;
begin
  Result := MaxDouble;
  for I := 0 to High(P) do
  begin
    for J := 1 to High(P[I].Pts) do
      Result := Min(Result, SegDist(X, Y, P[I].Pts[J - 1], P[I].Pts[J]));
    if P[I].Closed and (Length(P[I].Pts) > 2) then
      Result := Min(Result, SegDist(X, Y, P[I].Pts[High(P[I].Pts)], P[I].Pts[0]));
  end;
end;

end.
