unit makerouter_clip;

{ Ponte entre os caminhos da suite (TLPPaths, mm, Y para cima) e a Clipper2
  (src/shared/clipper2): offset com cantos arredondados e booleanas.
  Os poligonos fechados de saida repetem o primeiro ponto no fim (como
  LPIsClosed espera). Orientacao da Clipper: contorno externo com area
  positiva (anti-horario), furos com area negativa. }

{$mode objfpc}{$H+}

interface

uses
  Math, laserpcb_geom, Clipper;

const
  MR_CLIP_DECIMALS = 4;      { 0,0001 mm }
  MR_ARC_TOL = 0.005;        { erro de corda dos cantos arredondados (mm) }

function MRToClip(const P: TLPPaths): TPathsD;
function MRFromClip(const P: TPathsD; CloseThem: Boolean = True): TLPPaths;
{ uniao dos poligonos fechados; EvenOdd: formas dentro de formas viram furos }
function MRRegion(const P: TLPPaths; EvenOdd: Boolean): TLPPaths;
{ offset de regiao fechada: Delta > 0 cresce, < 0 encolhe (cantos redondos) }
function MROffset(const P: TLPPaths; Delta: Double): TLPPaths;
function MRUnion(const A, B: TLPPaths): TLPPaths;
function MRDifference(const A, B: TLPPaths): TLPPaths;
function MRIntersect(const A, B: TLPPaths): TLPPaths;
{ area com sinal da regiao (soma) }
function MRRegionArea(const P: TLPPaths): Double;
{ ponto dentro da regiao (regra nao-zero sobre o resultado da Clipper) }
function MRInside(const P: TLPPaths; X, Y: Double): Boolean;

implementation

function MRToClip(const P: TLPPaths): TPathsD;
var I, J, N: Integer;
begin
  Result := nil;
  SetLength(Result, Length(P));
  for I := 0 to High(P) do
  begin
    N := Length(P[I]);
    { a Clipper fecha sozinha: tira o ponto repetido }
    if (N > 1) and (LPDist(P[I][0], P[I][N - 1]) < 1e-9) then Dec(N);
    SetLength(Result[I], N);
    for J := 0 to N - 1 do
    begin
      Result[I][J].X := P[I][J].X;
      Result[I][J].Y := P[I][J].Y;
    end;
  end;
end;

function MRFromClip(const P: TPathsD; CloseThem: Boolean): TLPPaths;
var I, J, N, K: Integer;
begin
  Result := nil;
  K := 0;
  SetLength(Result, Length(P));
  for I := 0 to High(P) do
  begin
    N := Length(P[I]);
    if N < 2 then Continue;
    if CloseThem then SetLength(Result[K], N + 1) else SetLength(Result[K], N);
    for J := 0 to N - 1 do
      Result[K][J] := LPPoint(P[I][J].X, P[I][J].Y);
    if CloseThem then Result[K][N] := Result[K][0];
    Inc(K);
  end;
  SetLength(Result, K);
end;

function MRRegion(const P: TLPPaths; EvenOdd: Boolean): TLPPaths;
var FR: TFillRule;
begin
  if EvenOdd then FR := frEvenOdd else FR := frNonZero;
  Result := MRFromClip(Union(MRToClip(P), FR, MR_CLIP_DECIMALS));
end;

function MROffset(const P: TLPPaths; Delta: Double): TLPPaths;
begin
  if Length(P) = 0 then Exit(nil);
  if Abs(Delta) < 1e-9 then Exit(MRRegion(P, False));
  Result := MRFromClip(InflatePaths(MRToClip(P), Delta, jtRound, etPolygon, 2.0,
    MR_CLIP_DECIMALS, MR_ARC_TOL));
end;

function MRUnion(const A, B: TLPPaths): TLPPaths;
begin
  Result := MRFromClip(Union(MRToClip(A), MRToClip(B), frNonZero, MR_CLIP_DECIMALS));
end;

function MRDifference(const A, B: TLPPaths): TLPPaths;
begin
  Result := MRFromClip(Difference(MRToClip(A), MRToClip(B), frNonZero, MR_CLIP_DECIMALS));
end;

function MRIntersect(const A, B: TLPPaths): TLPPaths;
begin
  Result := MRFromClip(Intersect(MRToClip(A), MRToClip(B), frNonZero, MR_CLIP_DECIMALS));
end;

function MRRegionArea(const P: TLPPaths): Double;
var I: Integer;
begin
  Result := 0;
  for I := 0 to High(P) do Result := Result + LPSignedArea(P[I]);
end;

function MRInside(const P: TLPPaths; X, Y: Double): Boolean;
var I, J, W: Integer; A, B: TLPPoint;
begin
  W := 0;
  for I := 0 to High(P) do
    for J := 1 to High(P[I]) do
    begin
      A := P[I][J - 1]; B := P[I][J];
      if A.Y <= Y then
      begin
        if (B.Y > Y) and ((B.X - A.X) * (Y - A.Y) - (X - A.X) * (B.Y - A.Y) > 0) then Inc(W);
      end
      else if (B.Y <= Y) and ((B.X - A.X) * (Y - A.Y) - (X - A.X) * (B.Y - A.Y) < 0) then Dec(W);
    end;
  Result := W <> 0;
end;

end.
