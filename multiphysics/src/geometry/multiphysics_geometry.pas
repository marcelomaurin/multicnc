unit multiphysics_geometry;

{ Geometria das pecas para a malha FEM: primitivas do MultiAssembly (box, cyl,
  prism; ver models/components/README.md), em metros, com transformacao da
  peca e faces nomeadas.

  Cada primitiva tem um eixo de extrusao w e uma secao (u, v):
    z: u->X, v->Y, w->Z   x: u->Y, v->Z, w->X   y: u->Z, v->X, w->Y
  A caixa usa sempre o eixo z (u=X, v=Y, w=Z).

  Faces (ID estavel, alvo das condicoes de contorno):
    caixa:    xmin xmax ymin ymax zmin zmax
    cilindro: base topo lateral interna corte0 corte1
    prisma:   base topo lado0 .. ladoN-1 }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, multiphysics_vector;

type
  TGeoPrimKind = (gpBox, gpCyl, gpPrism);

  TVector2 = record
    U, V: Double;
  end;

  TGeoPrimitive = record
    Kind: TGeoPrimKind;
    ID: string;               { nome da primitiva dentro da peca }
    Axis: Char;               { 'x', 'y' ou 'z' (cilindro e prisma) }
    At: TVector3;             { caixa: canto minimo; cilindro: centro da base; prisma: origem }
    Size: TVector3;           { caixa }
    R, RI, R2, H: Double;     { cilindro: raio, raio interno (tubo), raio do topo (cone), altura }
    Arc0, Arc1: Double;       { setor em graus; Arc1 - Arc0 >= 360 = volta inteira }
    Rot: Double;              { fase em graus em torno do eixo }
    Poly: array of TVector2;  { prisma: poligono (u, v), anti-horario ou horario }
  end;

  { transformacao rigida: X_mundo = Rot * X_local + Pos }
  TGeoTransform = record
    M: array[0..2, 0..2] of Double;
    Pos: TVector3;
  end;

function V2(U, V: Double): TVector2;
function VDot(const A, B: TVector3): Double;
function VNormalize(const A: TVector3): TVector3;

function BoxPrim(const ID: string; const At, Size: TVector3): TGeoPrimitive;
function CylPrim(const ID: string; Axis: Char; const At: TVector3; R, H: Double;
  RI: Double = 0; R2: Double = -1): TGeoPrimitive;
function PrismPrim(const ID: string; Axis: Char; const At: TVector3; H: Double;
  const Poly: array of TVector2): TGeoPrimitive;

function IdentityTransform: TGeoTransform;
{ rotacoes em graus aplicadas na ordem X, depois Y, depois Z (eixos fixos) }
function EulerTransform(const Pos: TVector3; RX, RY, RZ: Double): TGeoTransform;
{ como o MultiAssembly: escala por eixo, gira (Z*Y*X) em torno do pivo e
  desloca: X_mundo = Pos + Pivo + R (S . X - Pivo) }
function AffineTransform(const Pos, Pivot, Scale: TVector3; RX, RY, RZ: Double): TGeoTransform;
function ApplyTransform(const T: TGeoTransform; const P: TVector3): TVector3;
function ApplyRotation(const T: TGeoTransform; const P: TVector3): TVector3;

{ ponto local da primitiva (u, v, w relativos a At) para coordenadas da peca }
function PrimLocalToPart(const P: TGeoPrimitive; U, V, W: Double): TVector3;

function IsFullCircle(const P: TGeoPrimitive): Boolean;
function PolygonArea(const Poly: array of TVector2): Double;   { com sinal: + anti-horario }
function PolygonCentroid(const Poly: array of TVector2): TVector2;
{ volume e centroide exatos (cone/tubo/setor inclusos), em coordenadas da peca }
function PrimVolume(const P: TGeoPrimitive): Double;
function PrimCentroid(const P: TGeoPrimitive): TVector3;
{ faces da primitiva (nomes curtos) }
function PrimFaceNames(const P: TGeoPrimitive): string;  { separados por virgula }

implementation

function V2(U, V: Double): TVector2;
begin
  Result.U := U; Result.V := V;
end;

function VDot(const A, B: TVector3): Double;
begin
  Result := A.X * B.X + A.Y * B.Y + A.Z * B.Z;
end;

function VNormalize(const A: TVector3): TVector3;
var
  L: Double;
begin
  L := VLength(A);
  if L > 0 then Result := VScale(A, 1 / L) else Result := A;
end;

function BlankPrim: TGeoPrimitive;
begin
  Result.Kind := gpBox; Result.ID := ''; Result.Axis := 'z';
  Result.At := V3(0, 0, 0); Result.Size := V3(0, 0, 0);
  Result.R := 0; Result.RI := 0; Result.R2 := 0; Result.H := 0;
  Result.Arc0 := 0; Result.Arc1 := 360; Result.Rot := 0;
  SetLength(Result.Poly, 0);
end;

function BoxPrim(const ID: string; const At, Size: TVector3): TGeoPrimitive;
begin
  Result := BlankPrim;
  Result.Kind := gpBox; Result.ID := ID; Result.At := At; Result.Size := Size;
end;

function CylPrim(const ID: string; Axis: Char; const At: TVector3; R, H: Double;
  RI: Double; R2: Double): TGeoPrimitive;
begin
  Result := BlankPrim;
  Result.Kind := gpCyl; Result.ID := ID; Result.Axis := LowerCase(Axis);
  Result.At := At; Result.R := R; Result.H := H; Result.RI := RI;
  if R2 < 0 then Result.R2 := R else Result.R2 := R2;
end;

function PrismPrim(const ID: string; Axis: Char; const At: TVector3; H: Double;
  const Poly: array of TVector2): TGeoPrimitive;
var
  I: Integer;
begin
  Result := BlankPrim;
  Result.Kind := gpPrism; Result.ID := ID; Result.Axis := LowerCase(Axis);
  Result.At := At; Result.H := H;
  SetLength(Result.Poly, Length(Poly));
  for I := 0 to High(Poly) do Result.Poly[I] := Poly[I];
end;

function IdentityTransform: TGeoTransform;
var
  I, J: Integer;
begin
  for I := 0 to 2 do
    for J := 0 to 2 do
      if I = J then Result.M[I, J] := 1 else Result.M[I, J] := 0;
  Result.Pos := V3(0, 0, 0);
end;

function EulerTransform(const Pos: TVector3; RX, RY, RZ: Double): TGeoTransform;
var
  S, Co: Double;
  I, J: Integer;

  procedure Mul(const X, Y: array of Double; out Z: array of Double);
  var
    P, Q, R: Integer;
  begin
    for P := 0 to 2 do
      for Q := 0 to 2 do
      begin
        Z[P * 3 + Q] := 0;
        for R := 0 to 2 do Z[P * 3 + Q] := Z[P * 3 + Q] + X[P * 3 + R] * Y[R * 3 + Q];
      end;
  end;

var
  RXm, RYm, RZm, T1, T2: array[0..8] of Double;
begin
  FillChar(RXm, SizeOf(RXm), 0); FillChar(RYm, SizeOf(RYm), 0); FillChar(RZm, SizeOf(RZm), 0);
  SinCos(DegToRad(RX), S, Co);
  RXm[0] := 1; RXm[4] := Co; RXm[5] := -S; RXm[7] := S; RXm[8] := Co;
  SinCos(DegToRad(RY), S, Co);
  RYm[0] := Co; RYm[2] := S; RYm[4] := 1; RYm[6] := -S; RYm[8] := Co;
  SinCos(DegToRad(RZ), S, Co);
  RZm[0] := Co; RZm[1] := -S; RZm[3] := S; RZm[4] := Co; RZm[8] := 1;
  { R = Rz * Ry * Rx (primeiro X) }
  Mul(RYm, RXm, T1);
  Mul(RZm, T1, T2);
  for I := 0 to 2 do
    for J := 0 to 2 do
      Result.M[I, J] := T2[I * 3 + J];
  Result.Pos := Pos;
end;

function AffineTransform(const Pos, Pivot, Scale: TVector3; RX, RY, RZ: Double): TGeoTransform;
var
  R: TGeoTransform;
  I: Integer;
begin
  R := EulerTransform(V3(0, 0, 0), RX, RY, RZ);
  Result := R;
  for I := 0 to 2 do
  begin
    Result.M[I, 0] := R.M[I, 0] * Scale.X;
    Result.M[I, 1] := R.M[I, 1] * Scale.Y;
    Result.M[I, 2] := R.M[I, 2] * Scale.Z;
  end;
  Result.Pos := VSub(VAdd(Pos, Pivot), ApplyRotation(R, Pivot));
end;

function ApplyRotation(const T: TGeoTransform; const P: TVector3): TVector3;
begin
  Result.X := T.M[0, 0] * P.X + T.M[0, 1] * P.Y + T.M[0, 2] * P.Z;
  Result.Y := T.M[1, 0] * P.X + T.M[1, 1] * P.Y + T.M[1, 2] * P.Z;
  Result.Z := T.M[2, 0] * P.X + T.M[2, 1] * P.Y + T.M[2, 2] * P.Z;
end;

function ApplyTransform(const T: TGeoTransform; const P: TVector3): TVector3;
begin
  Result := VAdd(ApplyRotation(T, P), T.Pos);
end;

function PrimLocalToPart(const P: TGeoPrimitive; U, V, W: Double): TVector3;
var
  D: TVector3;
begin
  if P.Kind = gpBox then
    D := V3(U, V, W)
  else
    case P.Axis of
      'x': D := V3(W, U, V);
      'y': D := V3(V, W, U);
      else D := V3(U, V, W);
    end;
  Result := VAdd(P.At, D);
end;

function IsFullCircle(const P: TGeoPrimitive): Boolean;
begin
  Result := (P.Arc1 - P.Arc0) >= 360 - 1e-9;
end;

function PolygonArea(const Poly: array of TVector2): Double;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 0 to High(Poly) do
  begin
    J := (I + 1) mod Length(Poly);
    Result := Result + Poly[I].U * Poly[J].V - Poly[J].U * Poly[I].V;
  end;
  Result := Result / 2;
end;

function PolygonCentroid(const Poly: array of TVector2): TVector2;
var
  I, J: Integer;
  A, Cr, CU, CV: Double;
begin
  A := PolygonArea(Poly);
  CU := 0; CV := 0;
  for I := 0 to High(Poly) do
  begin
    J := (I + 1) mod Length(Poly);
    Cr := Poly[I].U * Poly[J].V - Poly[J].U * Poly[I].V;
    CU := CU + (Poly[I].U + Poly[J].U) * Cr;
    CV := CV + (Poly[I].V + Poly[J].V) * Cr;
  end;
  if A <> 0 then Result := V2(CU / (6 * A), CV / (6 * A)) else Result := V2(0, 0);
end;

{ fracao da volta e meio-angulo do setor }
procedure ArcInfo(const P: TGeoPrimitive; out Frac, Half, Mid: Double);
var
  D: Double;
begin
  if IsFullCircle(P) then
  begin
    Frac := 1; Half := Pi; Mid := 0;
  end
  else
  begin
    D := DegToRad(P.Arc1 - P.Arc0);
    Frac := D / (2 * Pi);
    Half := D / 2;
    Mid := DegToRad((P.Arc0 + P.Arc1) / 2 + P.Rot);
  end;
end;

{ tronco de cone maciço de raios A (base) e B (topo), altura H: volume e
  altura do centroide }
procedure Frustum(A, B, H: Double; out Vol, Zc: Double);
var
  S: Double;
begin
  S := A * A + A * B + B * B;
  Vol := Pi * H * S / 3;
  if S > 0 then Zc := H * (A * A + 2 * A * B + 3 * B * B) / (4 * S) else Zc := 0;
end;

function PrimVolume(const P: TGeoPrimitive): Double;
var
  Vo, Vi, Z, Frac, Half, Mid: Double;
begin
  case P.Kind of
    gpBox: Result := P.Size.X * P.Size.Y * P.Size.Z;
    gpPrism: Result := Abs(PolygonArea(P.Poly)) * P.H;
    else
    begin
      ArcInfo(P, Frac, Half, Mid);
      Frustum(P.R, P.R2, P.H, Vo, Z);
      Vi := Pi * Sqr(P.RI) * P.H;
      Result := Frac * (Vo - Vi);
    end;
  end;
end;

function PrimCentroid(const P: TGeoPrimitive): TVector3;
var
  Vo, Vi, Zo, W, Frac, Half, Mid, Rc, S, Co: Double;
  C: TVector2;
  N, I: Integer;
  SR, M, Mt, R, R0, R1, Z0, Z1, Dz: Double;
begin
  case P.Kind of
    gpBox:
      Result := VAdd(P.At, VScale(P.Size, 0.5));
    gpPrism:
      begin
        C := PolygonCentroid(P.Poly);
        Result := PrimLocalToPart(P, C.U, C.V, P.H / 2);
      end;
    else
    begin
      ArcInfo(P, Frac, Half, Mid);
      Frustum(P.R, P.R2, P.H, Vo, Zo);
      Vi := Pi * Sqr(P.RI) * P.H;
      if Vo - Vi <= 0 then Exit(P.At);
      W := (Vo * Zo - Vi * P.H / 2) / (Vo - Vi);
      Rc := 0;
      if not IsFullCircle(P) then
      begin
        { distancia radial do centroide do setor: integra em fatias de altura
          (o raio externo varia no cone) }
        N := 400; SR := 0; Mt := 0;
        for I := 0 to N - 1 do
        begin
          Z0 := P.H * I / N; Z1 := P.H * (I + 1) / N; Dz := Z1 - Z0;
          R := P.R + (P.R2 - P.R) * (Z0 + Z1) / (2 * P.H);
          R0 := P.RI; R1 := R;
          M := (Sqr(R1) - Sqr(R0)) / 2 * Dz;             { area do setor / angulo }
          SR := SR + (Power(R1, 3) - Power(R0, 3)) / 3 * Dz;
          Mt := Mt + M;
        end;
        if (Mt > 0) and (Half > 0) then Rc := SR / Mt * Sin(Half) / Half;
      end;
      SinCos(Mid, S, Co);
      Result := PrimLocalToPart(P, Rc * Co, Rc * S, W);
    end;
  end;
end;

function PrimFaceNames(const P: TGeoPrimitive): string;
var
  I: Integer;
begin
  case P.Kind of
    gpBox: Result := 'xmin,xmax,ymin,ymax,zmin,zmax';
    gpPrism:
      begin
        Result := 'base,topo';
        for I := 0 to High(P.Poly) do Result := Result + ',lado' + IntToStr(I);
      end;
    else
    begin
      Result := 'base,topo,lateral';
      if P.RI > 0 then Result := Result + ',interna';
      if not IsFullCircle(P) then Result := Result + ',corte0,corte1';
    end;
  end;
end;

end.
