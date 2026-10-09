unit multicad_types;

{ MultiCAD - tipos geometricos basicos (fase 0).

  Unidades: mm e graus na interface; radianos so dentro das funcoes.
  Sistema de coordenadas igual ao SolidWorks: Y para cima.
  Planos padrao (ARCHITECTURE.md, secao 3A):
    Frontal  normal +Z, x do sketch +X, y do sketch +Y
    Superior normal +Y, x do sketch +X, y do sketch -Z
    Lateral  normal +X, x do sketch -Z, y do sketch +Y }

{$mode objfpc}{$H+}

interface

uses
  Math;

const
  CAD_TOL = 0.001;      { tolerancia do modelo em mm (solda, coincidencia) }
  CAD_EPS = 1E-12;      { zero numerico }
  CAD_ANGLE_TOL = 1E-6; { radianos }

type
  TCadVec2 = record
    X, Y: Double;
  end;

  TCadVec3 = record
    X, Y, Z: Double;
  end;

  { Matriz 4x4 em linhas: M[linha, coluna]; ponto como coluna (x, y, z, 1). }
  TCadMat4 = array[0..3, 0..3] of Double;

  { Referencial de um plano: origem, eixos do sketch e normal (N = X x Y). }
  TCadFrame = record
    Origin, XDir, YDir, Normal: TCadVec3;
  end;

  TCadBox3 = record
    Min, Max: TCadVec3;
    Empty: Boolean;
  end;

  TCadIdArray = array of Integer;
  TCadStrArray = array of string;

  TCadStdPlane = (spFrontal, spSuperior, spLateral);

  TCadFeatureKind = (cfOrigin, cfPlane, cfAxis, cfSketch, cfExtrude, cfCut,
    cfRevolve, cfRevolveCut, cfHole, cfFillet, cfChamfer, cfShell,
    cfLinearPattern, cfCircularPattern, cfMirror);

  TSketchEntityKind = (sePoint, seLine, seArc, seCircle, seEllipse, seSpline);

  TConstraintKind = (ckCoincident, ckHorizontal, ckVertical, ckParallel,
    ckPerpendicular, ckTangent, ckEqual, ckConcentric, ckMidpoint, ckFixed,
    ckSymmetric, ckDistance, ckHorizontalDistance, ckVerticalDistance,
    ckRadius, ckDiameter, ckAngle);

const
  CAD_FEATURE_CODES: array[TCadFeatureKind] of string = ('origin', 'plane',
    'axis', 'sketch', 'extrude', 'cut', 'revolve', 'revolve_cut', 'hole',
    'fillet', 'chamfer', 'shell', 'linear_pattern', 'circular_pattern',
    'mirror');
  { Nomes como no SolidWorks em portugues (decisao D6). }
  CAD_FEATURE_NAMES: array[TCadFeatureKind] of string = ('Origem', 'Plano',
    'Eixo', 'Esboço', 'Ressalto/Base extrudado', 'Corte extrudado',
    'Ressalto revolucionado', 'Corte revolucionado', 'Furo', 'Filete',
    'Chanfro', 'Casca', 'Padrão linear', 'Padrão circular', 'Espelhar');
  CAD_STD_PLANE_NAMES: array[TCadStdPlane] of string = ('Plano Frontal',
    'Plano Superior', 'Plano Lateral');
  CAD_ENTITY_CODES: array[TSketchEntityKind] of string = ('point', 'line',
    'arc', 'circle', 'ellipse', 'spline');
  CAD_CONSTRAINT_CODES: array[TConstraintKind] of string = ('coincident',
    'horizontal', 'vertical', 'parallel', 'perpendicular', 'tangent', 'equal',
    'concentric', 'midpoint', 'fixed', 'symmetric', 'distance',
    'hdistance', 'vdistance', 'radius', 'diameter', 'angle');

function V2(AX, AY: Double): TCadVec2;
function V3(AX, AY, AZ: Double): TCadVec3;
function VAdd(const A, B: TCadVec3): TCadVec3;
function VSub(const A, B: TCadVec3): TCadVec3;
function VScale(const A: TCadVec3; S: Double): TCadVec3;
function VNeg(const A: TCadVec3): TCadVec3;
function VDot(const A, B: TCadVec3): Double;
function VCross(const A, B: TCadVec3): TCadVec3;
function VLen(const A: TCadVec3): Double;
function VDist(const A, B: TCadVec3): Double;
function VNorm(const A: TCadVec3): TCadVec3;
function VSame(const A, B: TCadVec3; Tol: Double = CAD_TOL): Boolean;
function VLerp(const A, B: TCadVec3; T: Double): TCadVec3;

function MatIdentity: TCadMat4;
function MatTranslate(DX, DY, DZ: Double): TCadMat4;
{ Rotacao de AngleDeg graus em torno do eixo Axis passando pela origem. }
function MatRotate(const Axis: TCadVec3; AngleDeg: Double): TCadMat4;
function MatScale(S: Double): TCadMat4;
function MatMul(const A, B: TCadMat4): TCadMat4;
function MatPoint(const M: TCadMat4; const P: TCadVec3): TCadVec3;
function MatDir(const M: TCadMat4; const D: TCadVec3): TCadVec3;
{ Inversa de transformacao rigida (rotacao + translacao). }
function MatRigidInverse(const M: TCadMat4): TCadMat4;

function StdFrame(P: TCadStdPlane): TCadFrame;
{ Monta um referencial a partir de origem, normal e eixo X sugerido.
  Regra para faces planas: X = projecao do X global; se quase paralelo a
  normal, usa o Z global. }
function FrameFromNormal(const Origin, Normal: TCadVec3): TCadFrame;
function FrameValid(const F: TCadFrame): Boolean;
function FrameToWorld(const F: TCadFrame; const P: TCadVec2): TCadVec3;
function FrameToLocal(const F: TCadFrame; const P: TCadVec3): TCadVec2;
function FrameDistance(const F: TCadFrame; const P: TCadVec3): Double;
function FrameOffset(const F: TCadFrame; D: Double): TCadFrame;
function FrameMatrix(const F: TCadFrame): TCadMat4;

function BoxEmpty: TCadBox3;
procedure BoxAdd(var B: TCadBox3; const P: TCadVec3);
function BoxSize(const B: TCadBox3): TCadVec3;

function DegToRadC(D: Double): Double;
function RadToDegC(R: Double): Double;

implementation

function V2(AX, AY: Double): TCadVec2;
begin
  Result.X := AX;
  Result.Y := AY;
end;

function V3(AX, AY, AZ: Double): TCadVec3;
begin
  Result.X := AX;
  Result.Y := AY;
  Result.Z := AZ;
end;

function VAdd(const A, B: TCadVec3): TCadVec3;
begin
  Result := V3(A.X + B.X, A.Y + B.Y, A.Z + B.Z);
end;

function VSub(const A, B: TCadVec3): TCadVec3;
begin
  Result := V3(A.X - B.X, A.Y - B.Y, A.Z - B.Z);
end;

function VScale(const A: TCadVec3; S: Double): TCadVec3;
begin
  Result := V3(A.X * S, A.Y * S, A.Z * S);
end;

function VNeg(const A: TCadVec3): TCadVec3;
begin
  Result := V3(-A.X, -A.Y, -A.Z);
end;

function VDot(const A, B: TCadVec3): Double;
begin
  Result := A.X * B.X + A.Y * B.Y + A.Z * B.Z;
end;

function VCross(const A, B: TCadVec3): TCadVec3;
begin
  Result := V3(A.Y * B.Z - A.Z * B.Y, A.Z * B.X - A.X * B.Z,
    A.X * B.Y - A.Y * B.X);
end;

function VLen(const A: TCadVec3): Double;
begin
  Result := Sqrt(VDot(A, A));
end;

function VDist(const A, B: TCadVec3): Double;
begin
  Result := VLen(VSub(A, B));
end;

function VNorm(const A: TCadVec3): TCadVec3;
var
  L: Double;
begin
  L := VLen(A);
  if L < CAD_EPS then
    Result := V3(0, 0, 0)
  else
    Result := VScale(A, 1 / L);
end;

function VSame(const A, B: TCadVec3; Tol: Double): Boolean;
begin
  Result := VDist(A, B) <= Tol;
end;

function VLerp(const A, B: TCadVec3; T: Double): TCadVec3;
begin
  Result := VAdd(A, VScale(VSub(B, A), T));
end;

function MatIdentity: TCadMat4;
var
  I, J: Integer;
begin
  for I := 0 to 3 do
    for J := 0 to 3 do
      if I = J then
        Result[I, J] := 1
      else
        Result[I, J] := 0;
end;

function MatTranslate(DX, DY, DZ: Double): TCadMat4;
begin
  Result := MatIdentity;
  Result[0, 3] := DX;
  Result[1, 3] := DY;
  Result[2, 3] := DZ;
end;

function MatRotate(const Axis: TCadVec3; AngleDeg: Double): TCadMat4;
var
  A: TCadVec3;
  C, S, T: Double;
begin
  A := VNorm(Axis);
  C := Cos(DegToRadC(AngleDeg));
  S := Sin(DegToRadC(AngleDeg));
  T := 1 - C;
  Result := MatIdentity;
  Result[0, 0] := T * A.X * A.X + C;
  Result[0, 1] := T * A.X * A.Y - S * A.Z;
  Result[0, 2] := T * A.X * A.Z + S * A.Y;
  Result[1, 0] := T * A.X * A.Y + S * A.Z;
  Result[1, 1] := T * A.Y * A.Y + C;
  Result[1, 2] := T * A.Y * A.Z - S * A.X;
  Result[2, 0] := T * A.X * A.Z - S * A.Y;
  Result[2, 1] := T * A.Y * A.Z + S * A.X;
  Result[2, 2] := T * A.Z * A.Z + C;
end;

function MatScale(S: Double): TCadMat4;
begin
  Result := MatIdentity;
  Result[0, 0] := S;
  Result[1, 1] := S;
  Result[2, 2] := S;
end;

function MatMul(const A, B: TCadMat4): TCadMat4;
var
  I, J, K: Integer;
  Sum: Double;
begin
  for I := 0 to 3 do
    for J := 0 to 3 do
    begin
      Sum := 0;
      for K := 0 to 3 do
        Sum := Sum + A[I, K] * B[K, J];
      Result[I, J] := Sum;
    end;
end;

function MatPoint(const M: TCadMat4; const P: TCadVec3): TCadVec3;
begin
  Result.X := M[0, 0] * P.X + M[0, 1] * P.Y + M[0, 2] * P.Z + M[0, 3];
  Result.Y := M[1, 0] * P.X + M[1, 1] * P.Y + M[1, 2] * P.Z + M[1, 3];
  Result.Z := M[2, 0] * P.X + M[2, 1] * P.Y + M[2, 2] * P.Z + M[2, 3];
end;

function MatDir(const M: TCadMat4; const D: TCadVec3): TCadVec3;
begin
  Result.X := M[0, 0] * D.X + M[0, 1] * D.Y + M[0, 2] * D.Z;
  Result.Y := M[1, 0] * D.X + M[1, 1] * D.Y + M[1, 2] * D.Z;
  Result.Z := M[2, 0] * D.X + M[2, 1] * D.Y + M[2, 2] * D.Z;
end;

function MatRigidInverse(const M: TCadMat4): TCadMat4;
var
  I, J: Integer;
  T: TCadVec3;
begin
  Result := MatIdentity;
  for I := 0 to 2 do
    for J := 0 to 2 do
      Result[I, J] := M[J, I];
  T := MatDir(Result, V3(M[0, 3], M[1, 3], M[2, 3]));
  Result[0, 3] := -T.X;
  Result[1, 3] := -T.Y;
  Result[2, 3] := -T.Z;
end;

function StdFrame(P: TCadStdPlane): TCadFrame;
begin
  Result.Origin := V3(0, 0, 0);
  case P of
    spFrontal:
      begin
        Result.XDir := V3(1, 0, 0);
        Result.YDir := V3(0, 1, 0);
      end;
    spSuperior:
      begin
        Result.XDir := V3(1, 0, 0);
        Result.YDir := V3(0, 0, -1);
      end;
    spLateral:
      begin
        Result.XDir := V3(0, 0, -1);
        Result.YDir := V3(0, 1, 0);
      end;
  end;
  Result.Normal := VCross(Result.XDir, Result.YDir);
end;

function FrameFromNormal(const Origin, Normal: TCadVec3): TCadFrame;
var
  N, Ref: TCadVec3;
begin
  N := VNorm(Normal);
  Ref := V3(1, 0, 0);
  if Abs(VDot(Ref, N)) > 0.999 then
    Ref := V3(0, 0, 1);
  Result.Origin := Origin;
  Result.Normal := N;
  Result.XDir := VNorm(VSub(Ref, VScale(N, VDot(Ref, N))));
  Result.YDir := VCross(N, Result.XDir);
end;

function FrameValid(const F: TCadFrame): Boolean;
begin
  Result := (Abs(VLen(F.XDir) - 1) < 1E-9) and (Abs(VLen(F.YDir) - 1) < 1E-9)
    and (Abs(VDot(F.XDir, F.YDir)) < 1E-9)
    and VSame(VCross(F.XDir, F.YDir), F.Normal, 1E-9);
end;

function FrameToWorld(const F: TCadFrame; const P: TCadVec2): TCadVec3;
begin
  Result := VAdd(F.Origin, VAdd(VScale(F.XDir, P.X), VScale(F.YDir, P.Y)));
end;

function FrameToLocal(const F: TCadFrame; const P: TCadVec3): TCadVec2;
var
  D: TCadVec3;
begin
  D := VSub(P, F.Origin);
  Result := V2(VDot(D, F.XDir), VDot(D, F.YDir));
end;

function FrameDistance(const F: TCadFrame; const P: TCadVec3): Double;
begin
  Result := VDot(VSub(P, F.Origin), F.Normal);
end;

function FrameOffset(const F: TCadFrame; D: Double): TCadFrame;
begin
  Result := F;
  Result.Origin := VAdd(F.Origin, VScale(F.Normal, D));
end;

function FrameMatrix(const F: TCadFrame): TCadMat4;
begin
  Result := MatIdentity;
  Result[0, 0] := F.XDir.X; Result[0, 1] := F.YDir.X; Result[0, 2] := F.Normal.X;
  Result[1, 0] := F.XDir.Y; Result[1, 1] := F.YDir.Y; Result[1, 2] := F.Normal.Y;
  Result[2, 0] := F.XDir.Z; Result[2, 1] := F.YDir.Z; Result[2, 2] := F.Normal.Z;
  Result[0, 3] := F.Origin.X;
  Result[1, 3] := F.Origin.Y;
  Result[2, 3] := F.Origin.Z;
end;

function BoxEmpty: TCadBox3;
begin
  Result.Min := V3(0, 0, 0);
  Result.Max := V3(0, 0, 0);
  Result.Empty := True;
end;

procedure BoxAdd(var B: TCadBox3; const P: TCadVec3);
begin
  if B.Empty then
  begin
    B.Min := P;
    B.Max := P;
    B.Empty := False;
    Exit;
  end;
  B.Min := V3(Min(B.Min.X, P.X), Min(B.Min.Y, P.Y), Min(B.Min.Z, P.Z));
  B.Max := V3(Max(B.Max.X, P.X), Max(B.Max.Y, P.Y), Max(B.Max.Z, P.Z));
end;

function BoxSize(const B: TCadBox3): TCadVec3;
begin
  if B.Empty then
    Result := V3(0, 0, 0)
  else
    Result := VSub(B.Max, B.Min);
end;

function DegToRadC(D: Double): Double;
begin
  Result := D * Pi / 180;
end;

function RadToDegC(R: Double): Double;
begin
  Result := R * 180 / Pi;
end;

initialization
  { A suite inteira e UTF-8 (nomes com acento: "Esboço1", "Aço 1020").
    Sem isso, programas sem LCL convertem os textos do JSON para a pagina
    de codigo do sistema e os nomes deixam de bater. O LCL faz o mesmo. }
  DefaultSystemCodePage := CP_UTF8;

end.
