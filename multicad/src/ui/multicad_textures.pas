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

implementation

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
