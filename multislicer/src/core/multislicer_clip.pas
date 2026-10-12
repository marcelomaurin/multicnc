unit multislicer_clip;

{ MultiSlicer - ponte entre os poligonos do fatiador (TPolygons2D, mm) e a
  Clipper2 (src/shared/clipper2): uniao, diferenca, intersecao e offset de
  regioes. Mesmo esquema do makerouter_clip.

  Orientacao de saida da Clipper: contorno externo anti-horario (area
  positiva), furos horario - a mesma convencao dos Loops do pipeline.
  Os poligonos NAO repetem o primeiro ponto no fim. }

{$mode objfpc}{$H+}

interface

uses Math, multisuite_geometry, Clipper;

const
  MS_CLIP_DECIMALS = 4;     { 0,0001 mm }
  MS_ARC_TOL = 0.02;        { erro de corda dos cantos arredondados (mm) }

function ToClip(const P: TPolygons2D): TPathsD;
function FromClip(const P: TPathsD): TPolygons2D;
function RegionUnion(const A, B: TPolygons2D): TPolygons2D;
function RegionUnionAll(const A: TPolygons2D): TPolygons2D;
function RegionDifference(const A, B: TPolygons2D): TPolygons2D;
function RegionIntersect(const A, B: TPolygons2D): TPolygons2D;
{ Delta > 0 cresce, < 0 encolhe (cantos redondos) }
function RegionOffset(const P: TPolygons2D; Delta: Double): TPolygons2D;
{ abertura morfologica: tira faixas mais finas que 2 * R }
function RegionOpen(const P: TPolygons2D; R: Double): TPolygons2D;
function RegionArea(const P: TPolygons2D): Double;
{ so os contornos externos (sem os furos), preenchidos }
function RegionOuter(const P: TPolygons2D): TPolygons2D;
function RectPolygon(X0, Y0, X1, Y1: Double): TPolygon2D;
function CirclePolygon(CX, CY, R: Double; Sides: Integer = 24): TPolygon2D;

implementation

function ToClip(const P: TPolygons2D): TPathsD;
var I, J, N: Integer;
begin
  Result := nil;
  SetLength(Result, Length(P));
  for I := 0 to High(P) do
  begin
    N := Length(P[I]);
    if (N > 1) and (Abs(P[I][0].X - P[I][N - 1].X) < 1e-9) and (Abs(P[I][0].Y - P[I][N - 1].Y) < 1e-9) then Dec(N);
    SetLength(Result[I], N);
    for J := 0 to N - 1 do
    begin
      Result[I][J].X := P[I][J].X;
      Result[I][J].Y := P[I][J].Y;
    end;
  end;
end;

function FromClip(const P: TPathsD): TPolygons2D;
var I, J, K, N: Integer;
begin
  Result := nil;
  SetLength(Result, Length(P));
  K := 0;
  for I := 0 to High(P) do
  begin
    N := Length(P[I]);
    if N < 3 then Continue;
    SetLength(Result[K], N);
    for J := 0 to N - 1 do Result[K][J] := Pt(P[I][J].X, P[I][J].Y);
    Inc(K);
  end;
  SetLength(Result, K);
end;

function RegionUnion(const A, B: TPolygons2D): TPolygons2D;
begin
  if Length(B) = 0 then Exit(RegionUnionAll(A));
  if Length(A) = 0 then Exit(RegionUnionAll(B));
  Result := FromClip(Union(ToClip(A), ToClip(B), frNonZero, MS_CLIP_DECIMALS));
end;

function RegionUnionAll(const A: TPolygons2D): TPolygons2D;
begin
  if Length(A) = 0 then Exit(nil);
  Result := FromClip(Union(ToClip(A), frNonZero, MS_CLIP_DECIMALS));
end;

function RegionDifference(const A, B: TPolygons2D): TPolygons2D;
begin
  if Length(A) = 0 then Exit(nil);
  if Length(B) = 0 then Exit(RegionUnionAll(A));
  Result := FromClip(Difference(ToClip(A), ToClip(B), frNonZero, MS_CLIP_DECIMALS));
end;

function RegionIntersect(const A, B: TPolygons2D): TPolygons2D;
begin
  if (Length(A) = 0) or (Length(B) = 0) then Exit(nil);
  Result := FromClip(Intersect(ToClip(A), ToClip(B), frNonZero, MS_CLIP_DECIMALS));
end;

function RegionOffset(const P: TPolygons2D; Delta: Double): TPolygons2D;
begin
  if Length(P) = 0 then Exit(nil);
  if Abs(Delta) < 1e-9 then Exit(RegionUnionAll(P));
  Result := FromClip(InflatePaths(ToClip(P), Delta, jtRound, etPolygon, 2.0, MS_CLIP_DECIMALS, MS_ARC_TOL));
end;

function RegionOpen(const P: TPolygons2D; R: Double): TPolygons2D;
begin
  Result := RegionOffset(RegionOffset(P, -R), R);
end;

function RegionArea(const P: TPolygons2D): Double;
var I: Integer;
begin
  Result := 0;
  for I := 0 to High(P) do Result := Result + PolygonArea(P[I]);
end;

function RegionOuter(const P: TPolygons2D): TPolygons2D;
var I, K: Integer;
begin
  Result := nil;
  SetLength(Result, Length(P));
  K := 0;
  for I := 0 to High(P) do
    if PolygonArea(P[I]) > 0 then
    begin
      Result[K] := P[I];
      Inc(K);
    end;
  SetLength(Result, K);
end;

function RectPolygon(X0, Y0, X1, Y1: Double): TPolygon2D;
begin
  Result := nil;
  SetLength(Result, 4);
  Result[0] := Pt(Min(X0, X1), Min(Y0, Y1));
  Result[1] := Pt(Max(X0, X1), Min(Y0, Y1));
  Result[2] := Pt(Max(X0, X1), Max(Y0, Y1));
  Result[3] := Pt(Min(X0, X1), Max(Y0, Y1));
end;

function CirclePolygon(CX, CY, R: Double; Sides: Integer): TPolygon2D;
var I: Integer;
begin
  Result := nil;
  SetLength(Result, Sides);
  for I := 0 to Sides - 1 do
    Result[I] := Pt(CX + R * Cos(2 * Pi * I / Sides), CY + R * Sin(2 * Pi * I / Sides));
end;

end.
