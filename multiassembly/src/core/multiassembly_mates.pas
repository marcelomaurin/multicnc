unit multiassembly_mates;

{ Uniao de pecas por referencia geometrica (estilo SolidWorks Composer / ZW3D):
  escolhe-se uma face, furo ou eixo na peca que se move (A) e outra na peca de
  referencia (B); a peca A e girada e deslocada o minimo necessario para que
  as referencias coincidam.

  Tipos:
    mrCoincident  faces planas encostadas (normais opostas)
    mrDistance    faces planas paralelas a uma distancia
    mrConcentric  eixos alinhados (furo/eixo, cilindro/cilindro)
    mrInsert      concentrico + coincidente (parafuso no furo, motor no suporte)
    mrParallel    so alinha as direcoes

  Pose de um componente: Position = canto minimo da caixa sem rotacao,
  Rotation = angulos de Euler em graus (R = Rz * Ry * Rx) aplicados em torno do
  centro da caixa. Mundo(l) = Position + C + R * (l - C), C = Size / 2. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, multiassembly_types;

type
  TMat3 = array[0..2, 0..2] of Double;

function MatIdentity: TMat3;
function MatFromEuler(const RotDeg: TAssemblyVec3): TMat3;
function EulerFromMat(const M: TMat3): TAssemblyVec3;
function MatMul(const A, B: TMat3): TMat3;
function MatVec(const M: TMat3; const V: TAssemblyVec3): TAssemblyVec3;
function MatAxisAngle(const Axis: TAssemblyVec3; AngleRad: Double): TMat3;
function MatBetween(const FromDir, ToDir: TAssemblyVec3): TMat3;
function Vec3Cross(const A, B: TAssemblyVec3): TAssemblyVec3;

function LocalToWorld(const C: TAssemblyComponent; const Pos, Rot, L: TAssemblyVec3): TAssemblyVec3;
function LocalDirToWorld(const Rot, D: TAssemblyVec3): TAssemblyVec3;
function FeatureToWorld(const C: TAssemblyComponent; const Pos, Rot: TAssemblyVec3;
  const F: TMateFeature): TMateFeature;

{ Tipo sugerido para um par de referencias. False se o par nao combina. }
function SuggestMateKind(const FA, FB: TMateFeature; out Kind: TMechanicalRelationKind): Boolean;
function MateKindAllowed(const FA, FB: TMateFeature; Kind: TMechanicalRelationKind): Boolean;
function MateKindName(Kind: TMechanicalRelationKind): string;

{ Calcula a nova pose de A para satisfazer a uniao com a referencia (ja em
  coordenadas de mundo) de B. FA esta no sistema local de A. }
function SolveMatePose(const CA: TAssemblyComponent; const PosA, RotA: TAssemblyVec3;
  const FA: TMateFeature; const FBWorld: TMateFeature; Kind: TMechanicalRelationKind;
  Flipped: Boolean; SpinDeg, Distance: Double; out NewPos, NewRot: TAssemblyVec3): Boolean;

{ Eixo dominante (unitario em X, Y ou Z) mais proximo de uma direcao, usado
  pela analise de graus de liberdade. }
function DominantAxis(const D: TAssemblyVec3): TAssemblyVec3;

implementation

function Vec3Cross(const A, B: TAssemblyVec3): TAssemblyVec3;
begin
  Result := Vec3(A.Y * B.Z - A.Z * B.Y, A.Z * B.X - A.X * B.Z, A.X * B.Y - A.Y * B.X);
end;

function MatIdentity: TMat3;
var I, J: Integer;
begin
  for I := 0 to 2 do
    for J := 0 to 2 do
      Result[I, J] := IfThen(I = J, 1.0, 0.0);
end;

function MatFromEuler(const RotDeg: TAssemblyVec3): TMat3;
var
  CA, SA, CB, SB, CG, SG: Double;
begin
  CA := Cos(DegToRad(RotDeg.X)); SA := Sin(DegToRad(RotDeg.X));
  CB := Cos(DegToRad(RotDeg.Y)); SB := Sin(DegToRad(RotDeg.Y));
  CG := Cos(DegToRad(RotDeg.Z)); SG := Sin(DegToRad(RotDeg.Z));
  Result[0, 0] := CG * CB; Result[0, 1] := CG * SB * SA - SG * CA; Result[0, 2] := CG * SB * CA + SG * SA;
  Result[1, 0] := SG * CB; Result[1, 1] := SG * SB * SA + CG * CA; Result[1, 2] := SG * SB * CA - CG * SA;
  Result[2, 0] := -SB;     Result[2, 1] := CB * SA;                Result[2, 2] := CB * CA;
end;

function CleanAngle(A: Double): Double;
begin
  Result := RadToDeg(A);
  if Abs(Result) < 1e-9 then Result := 0;
  Result := Round(Result * 1e6) / 1e6;
end;

function EulerFromMat(const M: TMat3): TAssemblyVec3;
var
  SB: Double;
begin
  SB := EnsureRange(-M[2, 0], -1.0, 1.0);
  if Abs(SB) < 0.999999 then
  begin
    Result.Y := CleanAngle(ArcSin(SB));
    Result.X := CleanAngle(ArcTan2(M[2, 1], M[2, 2]));
    Result.Z := CleanAngle(ArcTan2(M[1, 0], M[0, 0]));
  end
  else
  begin
    { trava de cardan: fixa Z = 0 }
    Result.Y := CleanAngle(ArcSin(SB));
    Result.Z := 0;
    if SB > 0 then
      Result.X := CleanAngle(ArcTan2(M[0, 1], M[1, 1]))
    else
      Result.X := CleanAngle(ArcTan2(-M[0, 1], M[1, 1]));
  end;
end;

function MatMul(const A, B: TMat3): TMat3;
var I, J, K: Integer;
begin
  for I := 0 to 2 do
    for J := 0 to 2 do
    begin
      Result[I, J] := 0;
      for K := 0 to 2 do
        Result[I, J] := Result[I, J] + A[I, K] * B[K, J];
    end;
end;

function MatVec(const M: TMat3; const V: TAssemblyVec3): TAssemblyVec3;
begin
  Result.X := M[0, 0] * V.X + M[0, 1] * V.Y + M[0, 2] * V.Z;
  Result.Y := M[1, 0] * V.X + M[1, 1] * V.Y + M[1, 2] * V.Z;
  Result.Z := M[2, 0] * V.X + M[2, 1] * V.Y + M[2, 2] * V.Z;
end;

function MatAxisAngle(const Axis: TAssemblyVec3; AngleRad: Double): TMat3;
var
  U: TAssemblyVec3;
  C, S, T: Double;
begin
  U := Vec3Normalize(Axis);
  if Vec3Len(U) < 1e-9 then Exit(MatIdentity);
  C := Cos(AngleRad); S := Sin(AngleRad); T := 1 - C;
  Result[0, 0] := T * U.X * U.X + C;       Result[0, 1] := T * U.X * U.Y - S * U.Z; Result[0, 2] := T * U.X * U.Z + S * U.Y;
  Result[1, 0] := T * U.X * U.Y + S * U.Z; Result[1, 1] := T * U.Y * U.Y + C;       Result[1, 2] := T * U.Y * U.Z - S * U.X;
  Result[2, 0] := T * U.X * U.Z - S * U.Y; Result[2, 1] := T * U.Y * U.Z + S * U.X; Result[2, 2] := T * U.Z * U.Z + C;
end;

function AnyPerpendicular(const D: TAssemblyVec3): TAssemblyVec3;
begin
  if Abs(D.X) < 0.9 then
    Result := Vec3Normalize(Vec3Cross(D, Vec3(1, 0, 0)))
  else
    Result := Vec3Normalize(Vec3Cross(D, Vec3(0, 1, 0)));
end;

function MatBetween(const FromDir, ToDir: TAssemblyVec3): TMat3;
var
  A, B, Ax: TAssemblyVec3;
  C: Double;
begin
  A := Vec3Normalize(FromDir);
  B := Vec3Normalize(ToDir);
  C := EnsureRange(Vec3Dot(A, B), -1.0, 1.0);
  if C > 0.999999 then Exit(MatIdentity);
  if C < -0.999999 then Exit(MatAxisAngle(AnyPerpendicular(A), Pi));
  Ax := Vec3Cross(A, B);
  Result := MatAxisAngle(Ax, ArcCos(C));
end;

function LocalToWorld(const C: TAssemblyComponent; const Pos, Rot, L: TAssemblyVec3): TAssemblyVec3;
var
  Ctr: TAssemblyVec3;
begin
  Ctr := Vec3Mul(C.Size, 0.5);
  Result := Vec3Add(Vec3Add(Pos, Ctr), MatVec(MatFromEuler(Rot), Vec3Sub(L, Ctr)));
end;

function LocalDirToWorld(const Rot, D: TAssemblyVec3): TAssemblyVec3;
begin
  Result := Vec3Normalize(MatVec(MatFromEuler(Rot), D));
end;

function FeatureToWorld(const C: TAssemblyComponent; const Pos, Rot: TAssemblyVec3;
  const F: TMateFeature): TMateFeature;
begin
  Result := F;
  Result.PlanePoint := LocalToWorld(C, Pos, Rot, F.PlanePoint);
  Result.PlaneNormal := LocalDirToWorld(Rot, F.PlaneNormal);
  Result.AxisPoint := LocalToWorld(C, Pos, Rot, F.AxisPoint);
  Result.AxisDir := LocalDirToWorld(Rot, F.AxisDir);
end;

function MateKindAllowed(const FA, FB: TMateFeature; Kind: TMechanicalRelationKind): Boolean;
begin
  case Kind of
    mrCoincident, mrDistance: Result := FA.HasPlane and FB.HasPlane;
    mrConcentric: Result := FA.HasAxis and FB.HasAxis;
    mrInsert: Result := FA.HasAxis and FB.HasAxis and FA.HasPlane and FB.HasPlane;
    mrParallel: Result := (FA.HasPlane or FA.HasAxis) and (FB.HasPlane or FB.HasAxis);
  else
    Result := False;
  end;
end;

function SuggestMateKind(const FA, FB: TMateFeature; out Kind: TMechanicalRelationKind): Boolean;
begin
  Result := True;
  if MateKindAllowed(FA, FB, mrInsert) then Kind := mrInsert
  else if MateKindAllowed(FA, FB, mrConcentric) then Kind := mrConcentric
  else if MateKindAllowed(FA, FB, mrCoincident) then Kind := mrCoincident
  else
  begin
    Kind := mrParallel;
    Result := MateKindAllowed(FA, FB, mrParallel);
  end;
end;

function MateKindName(Kind: TMechanicalRelationKind): string;
begin
  case Kind of
    mrCoincident: Result := 'Coincidente';
    mrDistance: Result := 'Distância';
    mrConcentric: Result := 'Concêntrico';
    mrInsert: Result := 'Inserir (concêntrico + coincidente)';
    mrParallel: Result := 'Paralelo';
    mrFixed: Result := 'Fixo';
    mrSlider: Result := 'Deslizante';
    mrHinge: Result := 'Articulação';
    mrLeadScrew: Result := 'Fuso';
    mrBelt: Result := 'Correia';
    mrGear: Result := 'Engrenagem';
    mrAxis: Result := 'Eixo';
    mrCoupled: Result := 'Acoplado';
  else
    Result := 'Relação';
  end;
end;

function FeatureDir(const F: TMateFeature; PreferPlane: Boolean): TAssemblyVec3;
begin
  if (PreferPlane and F.HasPlane) or not F.HasAxis then
    Result := F.PlaneNormal
  else
    Result := F.AxisDir;
end;

function SolveMatePose(const CA: TAssemblyComponent; const PosA, RotA: TAssemblyVec3;
  const FA: TMateFeature; const FBWorld: TMateFeature; Kind: TMechanicalRelationKind;
  Flipped: Boolean; SpinDeg, Distance: Double; out NewPos, NewRot: TAssemblyVec3): Boolean;
var
  W: TMateFeature;
  RA, RD, RNew: TMat3;
  DirA, Target, Pivot, T, V, Ctr, CenterW, NewCenter, AxisPtA: TAssemblyVec3;
  D: Double;
  UsePlane: Boolean;
begin
  NewPos := PosA;
  NewRot := RotA;
  Result := MateKindAllowed(FA, FBWorld, Kind);
  if not Result then Exit;

  W := FeatureToWorld(CA, PosA, RotA, FA);
  UsePlane := Kind in [mrCoincident, mrDistance, mrInsert];

  { 1. rotacao: direcao de A contra (ou junto com) a de B }
  DirA := FeatureDir(W, UsePlane);
  if UsePlane then
  begin
    Target := Vec3Mul(FBWorld.PlaneNormal, -1);
    if Flipped then Target := FBWorld.PlaneNormal;
    Pivot := W.PlanePoint;
  end
  else
  begin
    Target := FeatureDir(FBWorld, Kind = mrParallel);
    if (Kind = mrConcentric) or (Kind = mrParallel) then
      if Vec3Dot(DirA, Target) < 0 then Target := Vec3Mul(Target, -1);
    if Flipped then Target := Vec3Mul(Target, -1);
    if W.HasAxis then Pivot := W.AxisPoint else Pivot := W.PlanePoint;
  end;
  RD := MatBetween(DirA, Target);
  if Abs(SpinDeg) > 1e-9 then
    RD := MatMul(MatAxisAngle(Target, DegToRad(SpinDeg)), RD);

  RA := MatFromEuler(RotA);
  RNew := MatMul(RD, RA);
  NewRot := EulerFromMat(RNew);

  { centro da caixa girado em torno do pivo }
  Ctr := Vec3Mul(CA.Size, 0.5);
  CenterW := Vec3Add(PosA, Ctr);
  NewCenter := Vec3Add(Pivot, MatVec(RD, Vec3Sub(CenterW, Pivot)));

  { 2. translacao minima }
  T := Vec3(0, 0, 0);
  case Kind of
    mrCoincident, mrDistance:
      begin
        D := Vec3Dot(Vec3Sub(FBWorld.PlanePoint, Pivot), FBWorld.PlaneNormal);
        if Kind = mrDistance then D := D + Distance;
        T := Vec3Mul(FBWorld.PlaneNormal, D);
      end;
    mrConcentric:
      begin
        V := Vec3Sub(FBWorld.AxisPoint, Pivot);
        T := Vec3Sub(V, Vec3Mul(FBWorld.AxisDir, Vec3Dot(V, FBWorld.AxisDir)));
      end;
    mrInsert:
      begin
        AxisPtA := Vec3Add(Pivot, MatVec(RD, Vec3Sub(W.AxisPoint, Pivot)));
        V := Vec3Sub(FBWorld.AxisPoint, AxisPtA);
        T := Vec3Sub(V, Vec3Mul(FBWorld.PlaneNormal, Vec3Dot(V, FBWorld.PlaneNormal)));
        D := Vec3Dot(Vec3Sub(FBWorld.PlanePoint, Pivot), FBWorld.PlaneNormal) + Distance;
        T := Vec3Add(T, Vec3Mul(FBWorld.PlaneNormal, D));
      end;
  end;
  NewCenter := Vec3Add(NewCenter, T);
  NewPos := Vec3Sub(NewCenter, Ctr);
end;

function DominantAxis(const D: TAssemblyVec3): TAssemblyVec3;
begin
  if (Abs(D.X) >= Abs(D.Y)) and (Abs(D.X) >= Abs(D.Z)) then Result := Vec3(1, 0, 0)
  else if Abs(D.Y) >= Abs(D.Z) then Result := Vec3(0, 1, 0)
  else Result := Vec3(0, 0, 1);
end;

end.
