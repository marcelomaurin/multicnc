unit multicad_textures;

{ MultiCAD - texturas dos materiais (aparencia). Sem LCL.

  Mapas de luminancia 64x64 repetiveis gerados por tools/gen_textures.py
  (copia em data/textures/*.png) e embutidos no executavel
  (multicad_textures.inc). O renderizador multiplica a cor do material pelo
  valor da textura (128 = neutro), com projecao pelos tres planos
  (triplanar): a face usa o plano de coordenadas mais de frente para ela. }

{$mode objfpc}{$H+}

interface

uses
  Math, multicad_types;

{$I multicad_textures.inc}

{ Indice da textura pelo nome ("wood", "brushed"...); 0 = lisa. }
function CadTextureIndex(const AName: string): Integer;
{ Fator de cor (~0,6 a 1,25) no ponto P (mm) de uma face com normal N. }
function CadTexFactor(ATex: Integer; const P, N: TCadVec3): Double;
{ Igual, com filtro como nos jogos (mipmap + bilinear): APixelMM = tamanho de
  um pixel da tela em mm. Sem isso a textura "cintila" ao girar ou dar zoom. }
function CadTexFactorLod(ATex: Integer; const P, N: TCadVec3; APixelMM: Double): Double;

implementation

const
  MIP_LEVELS = 7;   { 64, 32, 16, 8, 4, 2, 1 }

var
  GMip: array of array[0..MIP_LEVELS - 1] of array of Single;
  GMipReady: Boolean;

procedure BuildMips;
var
  T, L, X, Y, S, S2: Integer;
begin
  SetLength(GMip, CAD_TEX_COUNT);
  for T := 0 to CAD_TEX_COUNT - 1 do
  begin
    SetLength(GMip[T][0], CAD_TEX_SIZE * CAD_TEX_SIZE);
    for X := 0 to CAD_TEX_SIZE * CAD_TEX_SIZE - 1 do
      GMip[T][0][X] := CAD_TEX_DATA[T, X] / 128;
    S := CAD_TEX_SIZE;
    for L := 1 to MIP_LEVELS - 1 do
    begin
      S2 := S div 2;
      SetLength(GMip[T][L], S2 * S2);
      for Y := 0 to S2 - 1 do
        for X := 0 to S2 - 1 do
          GMip[T][L][Y * S2 + X] := (GMip[T][L - 1][(2 * Y) * S + 2 * X] +
            GMip[T][L - 1][(2 * Y) * S + 2 * X + 1] + GMip[T][L - 1][(2 * Y + 1) * S + 2 * X] +
            GMip[T][L - 1][(2 * Y + 1) * S + 2 * X + 1]) / 4;
      S := S2;
    end;
  end;
  GMipReady := True;
end;

function SampleBilinear(ATex, ALevel: Integer; U, V: Double): Double;
var
  S, X0, Y0, X1, Y1: Integer;
  FX, FY, A, B: Double;
  M: array of Single;
begin
  S := CAD_TEX_SIZE shr ALevel;
  M := GMip[ATex][ALevel];
  U := U * S - 0.5;
  V := V * S - 0.5;
  X0 := Floor(U);
  Y0 := Floor(V);
  FX := U - X0;
  FY := V - Y0;
  X0 := X0 mod S; if X0 < 0 then Inc(X0, S);
  Y0 := Y0 mod S; if Y0 < 0 then Inc(Y0, S);
  X1 := (X0 + 1) mod S;
  Y1 := (Y0 + 1) mod S;
  A := M[Y0 * S + X0] * (1 - FX) + M[Y0 * S + X1] * FX;
  B := M[Y1 * S + X0] * (1 - FX) + M[Y1 * S + X1] * FX;
  Result := A * (1 - FY) + B * FY;
end;

function CadTexFactorLod(ATex: Integer; const P, N: TCadVec3; APixelMM: Double): Double;
var
  S, AX, AY, AZ, U, V, TexelsPerPixel, Lv: Double;
  L: Integer;
begin
  if (ATex <= 0) or (ATex >= CAD_TEX_COUNT) then
    Exit(1);
  if not GMipReady then
    BuildMips;
  S := 1 / CAD_TEX_SCALE[ATex];
  AX := Abs(N.X);
  AY := Abs(N.Y);
  AZ := Abs(N.Z);
  if (AX >= AY) and (AX >= AZ) then
  begin
    U := P.Z * S; V := P.Y * S;
  end
  else if AY >= AZ then
  begin
    U := P.X * S; V := P.Z * S;
  end
  else
  begin
    U := P.X * S; V := P.Y * S;
  end;
  { nivel do mipmap: quantos texels caem num pixel }
  TexelsPerPixel := APixelMM * S * CAD_TEX_SIZE;
  if TexelsPerPixel <= 1 then
    L := 0
  else
  begin
    Lv := Ln(TexelsPerPixel) / Ln(2);
    L := Ceil(Lv);
    if L >= MIP_LEVELS then
      L := MIP_LEVELS - 1;
  end;
  Result := SampleBilinear(ATex, L, U, V);
end;

function CadTextureIndex(const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to CAD_TEX_COUNT - 1 do
    if CAD_TEX_NAMES[I] = AName then
      Exit(I);
  Result := 0;
end;

function Sample(ATex: Integer; U, V: Double): Double;
var
  X, Y: Integer;
begin
  X := Floor(U * CAD_TEX_SIZE) mod CAD_TEX_SIZE;
  Y := Floor(V * CAD_TEX_SIZE) mod CAD_TEX_SIZE;
  if X < 0 then Inc(X, CAD_TEX_SIZE);
  if Y < 0 then Inc(Y, CAD_TEX_SIZE);
  Result := CAD_TEX_DATA[ATex, Y * CAD_TEX_SIZE + X];
end;

function CadTexFactor(ATex: Integer; const P, N: TCadVec3): Double;
var
  S, AX, AY, AZ: Double;
begin
  if (ATex <= 0) or (ATex >= CAD_TEX_COUNT) then
    Exit(1);
  S := 1 / CAD_TEX_SCALE[ATex];
  AX := Abs(N.X);
  AY := Abs(N.Y);
  AZ := Abs(N.Z);
  { veio/escovado ao longo do maior eixo da face }
  if (AX >= AY) and (AX >= AZ) then
    Result := Sample(ATex, P.Z * S, P.Y * S)
  else if AY >= AZ then
    Result := Sample(ATex, P.X * S, P.Z * S)
  else
    Result := Sample(ATex, P.X * S, P.Y * S);
  Result := Result / 128;
end;

end.
