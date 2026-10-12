unit multicad_sketchtrim;

{ Aparar retas ate as intersecoes mais proximas no proprio esboco.
  A previa usa o ponto real do cursor, sem captura ou inferencia. }

{$mode objfpc}{$H+}

interface

uses Math, multicad_types, multicad_sketch;

type
  TCadTrimSegment = record
    EntityId: Integer;
    Boundary0, Boundary1: Integer;
    T0, T1: Double;
    A, B: TCadVec2;
  end;

function CadSketchTrimPreview(S: TCadSketch; const P: TCadVec2;
  PickTol: Double; out Segment: TCadTrimSegment): Boolean;

implementation

const TRIM_EPS = 1E-8; { mm }

function Cross(const A, B: TCadVec2): Double;
begin Result := A.X * B.Y - A.Y * B.X; end;

function Sub(const A, B: TCadVec2): TCadVec2;
begin Result := V2(A.X - B.X, A.Y - B.Y); end;

function Dot(const A, B: TCadVec2): Double;
begin Result := A.X * B.X + A.Y * B.Y; end;

function OnArc(const E: TSketchEntity; const P: TCadVec2): Boolean;
var Start, Sweep, Angle: Double;
begin
  if E.Kind = seCircle then Exit(True);
  Start := ArcTan2(E.P2.Y - E.P1.Y, E.P2.X - E.P1.X);
  Sweep := ArcTan2(E.P3.Y - E.P1.Y, E.P3.X - E.P1.X) - Start;
  while Sweep <= 0 do Sweep := Sweep + 2 * Pi;
  Angle := ArcTan2(P.Y - E.P1.Y, P.X - E.P1.X) - Start;
  while Angle < 0 do Angle := Angle + 2 * Pi;
  while Angle >= 2 * Pi do Angle := Angle - 2 * Pi;
  Result := (Angle <= Sweep + 1E-9) or (2 * Pi - Angle < 1E-9);
end;

function CadSketchTrimPreview(S: TCadSketch; const P: TCadVec2;
  PickTol: Double; out Segment: TCadTrimSegment): Boolean;
var
  I, J, BestIndex, TempBoundary: Integer;
  E, Boundary: TSketchEntity;
  D, V, W, Q: TCadVec2;
  L2, Len, T, U, Distance, Best, ClickT, ParamEps, Den, VL,
    CenterT, Height2, Offset, Temp: Double;
  Cuts: array of Double;
  Boundaries: array of Integer;

  function At(AParam: Double): TCadVec2;
  begin Result := V2(E.P1.X + D.X * AParam, E.P1.Y + D.Y * AParam); end;

  procedure AddCut(AParam: Double; BoundaryId: Integer);
  var K: Integer;
  begin
    if IsNan(AParam) or IsInfinite(AParam) or
      (AParam < -ParamEps) or (AParam > 1 + ParamEps) then Exit;
    AParam := EnsureRange(AParam, 0, 1);
    for K := 0 to High(Cuts) do
      if Abs(Cuts[K] - AParam) <= ParamEps then Exit;
    SetLength(Cuts, Length(Cuts) + 1);
    SetLength(Boundaries, Length(Cuts));
    Cuts[High(Cuts)] := AParam;
    Boundaries[High(Cuts)] := BoundaryId;
  end;

  procedure CircleCut(AParam: Double);
  begin
    if OnArc(Boundary, At(AParam)) then AddCut(AParam, Boundary.Id);
  end;

begin
  Segment := Default(TCadTrimSegment);
  Result := False;
  if (S = nil) or IsNan(P.X) or IsNan(P.Y) or IsInfinite(P.X) or
    IsInfinite(P.Y) or IsNan(PickTol) or IsInfinite(PickTol) or (PickTol <= 0) then Exit;
  BestIndex := -1;
  Best := PickTol;
  ClickT := 0;
  for I := 0 to S.EntityCount - 1 do
  begin
    E := S.Entity(I);
    if (E.Kind <> seLine) or (E.SourceRef <> '') then Continue;
    D := Sub(E.P2, E.P1);
    L2 := Dot(D, D);
    if L2 <= Sqr(TRIM_EPS) then Continue;
    T := EnsureRange(Dot(Sub(P, E.P1), D) / L2, 0, 1);
    Q := V2(E.P1.X + T * D.X, E.P1.Y + T * D.Y);
    Distance := Sqrt(Sqr(P.X - Q.X) + Sqr(P.Y - Q.Y));
    if (Distance <= Best) and ((BestIndex < 0) or (Distance < Best - TRIM_EPS)) then
    begin
      Best := Distance;
      BestIndex := I;
      ClickT := T;
    end;
  end;
  if BestIndex < 0 then Exit;
  E := S.Entity(BestIndex);
  D := Sub(E.P2, E.P1);
  L2 := Dot(D, D);
  Len := Sqrt(L2);
  ParamEps := TRIM_EPS / Len;
  Cuts := nil; Boundaries := nil;
  AddCut(0, 0); AddCut(1, 0);
  for I := 0 to S.EntityCount - 1 do
  begin
    if I = BestIndex then Continue;
    Boundary := S.Entity(I);
    if Boundary.SourceRef <> '' then Continue;
    W := Sub(Boundary.P1, E.P1);
    case Boundary.Kind of
      seLine:
        begin
          V := Sub(Boundary.P2, Boundary.P1);
          VL := Sqrt(Dot(V, V));
          if VL <= TRIM_EPS then Continue;
          Den := Cross(D, V);
          if Abs(Den) <= 1E-12 * Len * VL then
          begin
            { Segmentos colineares: os limites da sobreposicao sao cortes. }
            if Abs(Cross(W, D)) <= TRIM_EPS * Len then
            begin
              AddCut(Dot(W, D) / L2, Boundary.Id);
              AddCut(Dot(Sub(Boundary.P2, E.P1), D) / L2, Boundary.Id);
            end;
          end
          else
          begin
            T := Cross(W, V) / Den;
            U := Cross(W, D) / Den;
            if (U >= -TRIM_EPS / VL) and (U <= 1 + TRIM_EPS / VL) then AddCut(T, Boundary.Id);
          end;
        end;
      seCircle, seArc:
        if Boundary.Radius > TRIM_EPS then
        begin
          CenterT := Dot(W, D) / L2;
          Height2 := Sqr(Boundary.Radius) - Sqr(Cross(W, D)) / L2;
          if Height2 < -TRIM_EPS * Max(1, Boundary.Radius) then Continue;
          Offset := Sqrt(Max(0, Height2) / L2);
          CircleCut(CenterT - Offset);
          CircleCut(CenterT + Offset);
        end;
    end;
  end;
  for I := 1 to High(Cuts) do
  begin
    Temp := Cuts[I]; TempBoundary := Boundaries[I]; J := I - 1;
    while (J >= 0) and (Cuts[J] > Temp) do
    begin Cuts[J + 1] := Cuts[J]; Boundaries[J + 1] := Boundaries[J]; Dec(J); end;
    Cuts[J + 1] := Temp;
    Boundaries[J + 1] := TempBoundary;
  end;
  { Um clique exatamente no cruzamento e ambiguo: nao apagar um lado ao acaso. }
  for I := 1 to High(Cuts) - 1 do
    if Abs(ClickT - Cuts[I]) <= ParamEps then Exit;
  for I := 1 to High(Cuts) do
    if (ClickT <= Cuts[I]) and (Cuts[I] - Cuts[I - 1] > ParamEps) then
    begin
      Segment.EntityId := E.Id;
      Segment.T0 := Cuts[I - 1]; Segment.T1 := Cuts[I];
      Segment.Boundary0 := Boundaries[I - 1]; Segment.Boundary1 := Boundaries[I];
      Segment.A := At(Segment.T0); Segment.B := At(Segment.T1);
      Exit(True);
    end;
end;

end.
