unit multislicer_scene;

{ MultiSlicer - cena de impressao (Etapa 3 do docs/PLANO_TAREFAS.md). Sem LCL.

  A cena guarda as pecas colocadas na mesa. Cada peca (TSliceObject) guarda a
  malha original do arquivo e a sua transformacao; a malha na mesa
  (WorldMesh) e recalculada so quando a transformacao muda.

  Transformacao, nesta ordem, em torno do centro da caixa da malha original:
    escala por eixo (espelho = escala negativa)
    -> rotacao X, depois Y, depois Z (graus)
    -> translacao: o centro XY da caixa vai para (X, Y) da mesa e o ponto
       mais baixo vai para Z = Lift (0 = assentada na mesa, como no Cura).
  Espelho em numero impar de eixos inverte a ordem dos vertices de cada
  triangulo, para as normais continuarem para fora.

  Coordenadas da mesa: origem no canto inferior esquerdo, Z para cima, mm.
  O fatiamento usa MergedMesh (todas as pecas ja na mesa).

  Etapa 4: deitar face na mesa (por triangulo ou automatico pela maior area
  plana), auto-arranjo, travar e desfazer/refazer das transformacoes (cada
  peca tem um Id unico; o historico guarda so os parametros, nao as malhas). }

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, Contnrs, Generics.Collections, multislicer_types, multislicer_mesh;

type
  TBox3 = record
    Min, Max: TVec3;
    Empty: Boolean;
  end;

  TMat3 = array[0..2, 0..2] of Double;

  { parametros de uma peca, para desfazer/refazer }
  TTransformState = record
    Id: Integer;
    X, Y, Lift, RotX, RotY, RotZ, ScaleX, ScaleY, ScaleZ: Double;
    MirrorX, MirrorY, MirrorZ, Locked: Boolean;
  end;
  TSceneState = array of TTransformState;

  { haste de apoio manual, presa a uma peca: posicao relativa ao centro da peca.
    Se a peca muda de forma (gira, escala, espelha) a haste deixa de valer. }
  TScenePillar = record
    ObjId, Shape: Integer;
    DX, DY, ZTop, Diameter: Double;
  end;

  { bloqueador de suporte: caixa na mesa, do Z = 0 ate a altura H }
  TSceneBlocker = record
    CX, CY, W, D, H: Double;
  end;

  TSliceObject = class
  private
    FSource: TMesh;           { malha original (posse) }
    FWorld: TMesh;            { malha na mesa (cache) }
    FWorldBox: TBox3;
    FDirty: Boolean;
    FVersion: Integer;
    FShapeVersion: Integer;
    FSourceCenter: TVec3;
    FX, FY, FLift: Double;
    FRotX, FRotY, FRotZ: Double;
    FScaleX, FScaleY, FScaleZ: Double;
    FMirrorX, FMirrorY, FMirrorZ: Boolean;
    FId: Integer;
    procedure Rebuild;
    procedure Changed;
    procedure SetX(V: Double);
    procedure SetY(V: Double);
    procedure SetLift(V: Double);
    procedure SetRotX(V: Double);
    procedure SetRotY(V: Double);
    procedure SetRotZ(V: Double);
    procedure SetScaleX(V: Double);
    procedure SetScaleY(V: Double);
    procedure SetScaleZ(V: Double);
    procedure SetMirrorX(V: Boolean);
    procedure SetMirrorY(V: Boolean);
    procedure SetMirrorZ(V: Boolean);
    function GetWorld: TMesh;
    function GetWorldBox: TBox3;
  public
    Name, SourceFile: string;
    Selected, Locked: Boolean;
    constructor Create(ASource: TMesh; const AName, AFile: string);  { assume a posse de ASource }
    destructor Destroy; override;
    function Clone: TSliceObject;
    procedure MoveBy(DX, DY: Double);
    procedure SetScaleUniform(S: Double);
    function TransformPoint(const P: TVec3): TVec3;
    function SourceSize: TVec3;
    function Size: TVec3;                       { tamanho na mesa }
    function GetState: TTransformState;
    procedure SetState(const S: TTransformState);
    procedure SetRotation(AX, AY, AZ: Double);
    { gira para a normal N (na mesa) ficar para baixo, apoiada na mesa }
    procedure AlignNormalDown(const N: TVec3);
    { gira Deg graus em torno de um eixo da mesa (0 = X, 1 = Y, 2 = Z) }
    procedure RotateWorld(Axis: Integer; Deg: Double);
    { deita na mesa o triangulo Index da malha na mesa }
    procedure LayFlatTriangle(Index: Integer);
    { deita na mesa a face plana que da a maior area de apoio; False se nada mudou }
    function LayFlatAuto: Boolean;
    { area de apoio na mesa (triangulos virados para baixo, em Z minimo), mm2 }
    function ContactArea: Double;
    property Id: Integer read FId;
    property Source: TMesh read FSource;
    property WorldMesh: TMesh read GetWorld;
    property WorldBox: TBox3 read GetWorldBox;
    property Version: Integer read FVersion;            { muda a cada alteracao, inclusive arrastar }
    property ShapeVersion: Integer read FShapeVersion;  { muda quando a forma muda (nao ao arrastar) }
    property X: Double read FX write SetX;
    property Y: Double read FY write SetY;
    property Lift: Double read FLift write SetLift;
    property RotX: Double read FRotX write SetRotX;
    property RotY: Double read FRotY write SetRotY;
    property RotZ: Double read FRotZ write SetRotZ;
    property ScaleX: Double read FScaleX write SetScaleX;
    property ScaleY: Double read FScaleY write SetScaleY;
    property ScaleZ: Double read FScaleZ write SetScaleZ;
    property MirrorX: Boolean read FMirrorX write SetMirrorX;
    property MirrorY: Boolean read FMirrorY write SetMirrorY;
    property MirrorZ: Boolean read FMirrorZ write SetMirrorZ;
  end;

  TSliceScene = class
  private
    FItems: TObjectList;
    FVersion: Integer;
    FUndo, FRedo: array of TSceneState;
    FPillars: array of TScenePillar;
    FBlockers: array of TSceneBlocker;
    function GetItem(I: Integer): TSliceObject;
    function FindSpotAmong(SX, SY: Double; const Obstacles: array of TBox3; out PX, PY: Double): Boolean;
    function Capture: TSceneState;
    procedure Apply(const St: TSceneState);
  public
    BedX, BedY, BedZ: Double;
    Spacing: Double;      { folga minima entre pecas (mm) }
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function Count: Integer;
    { Acrescenta a peca (posse de AMesh) num lugar livre da mesa. }
    function Add(AMesh: TMesh; const AName, AFile: string): TSliceObject;
    function AddObject(O: TSliceObject; FindPlace: Boolean): TSliceObject;
    procedure Delete(I: Integer);
    procedure DeleteSelected;
    function Duplicate(I: Integer): TSliceObject;
    function IndexOf(O: TSliceObject): Integer;
    procedure SelectOnly(I: Integer);    { -1 = nenhuma }
    procedure ToggleSelect(I: Integer);
    function SelectedCount: Integer;
    function FirstSelected: Integer;
    procedure CenterObject(I: Integer);
    { Primeiro lugar livre (centro da caixa) para uma peca do tamanho dado. }
    function FindFreeSpot(SX, SY: Double; Ignore: Integer; out PX, PY: Double): Boolean;
    function Overlaps(I, J: Integer): Boolean;
    function Inside(I: Integer): Boolean;
    function Validate(Errors: TStrings): Boolean;
    procedure MergedMesh(Dest: TMesh);
    function Bounds: TBox3;
    function TriangleCount: Integer;
    procedure Touch;                     { avisa mudanca (vista redesenha) }
    function FindById(AId: Integer): TSliceObject;
    { organiza as pecas destravadas a partir do centro, maiores primeiro;
      False se alguma nao coube }
    function Arrange: Boolean;
    function DuplicateN(I, N: Integer): Integer;   { devolve quantas couberam }
    { desfazer/refazer: chame PushUndo ANTES de alterar }
    procedure PushUndo;
    function Undo: Boolean;
    function Redo: Boolean;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    procedure ClearHistory;
    { hastes manuais }
    procedure AddPillar(O: TSliceObject; X, Y, ZTop, Diameter: Double);
    procedure ClearPillars;
    function PillarCount: Integer;
    function Pillar(I: Integer): TScenePillar;
    { posicao absoluta; False se a peca sumiu ou mudou de forma }
    function PillarAbs(I: Integer; out X, Y, ZTop, Diameter: Double): Boolean;
    function RemoveInvalidPillars: Integer;
    { bloqueadores }
    function AddBlocker(const B: TSceneBlocker): Integer;
    procedure SetBlocker(I: Integer; const B: TSceneBlocker);
    procedure DeleteBlocker(I: Integer);
    function BlockerCount: Integer;
    function Blocker(I: Integer): TSceneBlocker;
    property Items[I: Integer]: TSliceObject read GetItem; default;
    property Version: Integer read FVersion;
  end;

function MeshBox(M: TMesh): TBox3;
procedure BoxInclude(var B: TBox3; const P: TVec3);
function Vec3(AX, AY, AZ: Double): TVec3;
function TriNormal(const T: TTriangle): TVec3;   { unitaria (0 se degenerado) }
function TriArea(const T: TTriangle): Double;
{ R = Rz * Ry * Rx (graus), a mesma ordem de TransformPoint }
function EulerToMatrix(AX, AY, AZ: Double): TMat3;
procedure MatrixToEuler(const M: TMat3; out AX, AY, AZ: Double);
function MatMul3(const A, B: TMat3): TMat3;
function AxisAngle(const Axis: TVec3; AngleRad: Double): TMat3;

implementation

var
  NextObjectId: Integer = 0;

function Cross(const A, B: TVec3): TVec3;
begin
  Result := Vec3(A.Y * B.Z - A.Z * B.Y, A.Z * B.X - A.X * B.Z, A.X * B.Y - A.Y * B.X);
end;

function Dot(const A, B: TVec3): Double;
begin
  Result := A.X * B.X + A.Y * B.Y + A.Z * B.Z;
end;

function Sub(const A, B: TVec3): TVec3;
begin
  Result := Vec3(A.X - B.X, A.Y - B.Y, A.Z - B.Z);
end;

function TriNormal(const T: TTriangle): TVec3;
var L: Double;
begin
  Result := Cross(Sub(T.B, T.A), Sub(T.C, T.A));
  L := Sqrt(Dot(Result, Result));
  if L < 1e-12 then Result := Vec3(0, 0, 0)
  else Result := Vec3(Result.X / L, Result.Y / L, Result.Z / L);
end;

function TriArea(const T: TTriangle): Double;
var C: TVec3;
begin
  C := Cross(Sub(T.B, T.A), Sub(T.C, T.A));
  Result := 0.5 * Sqrt(Dot(C, C));
end;

function MatMul3(const A, B: TMat3): TMat3;
var I, J, K: Integer;
begin
  for I := 0 to 2 do
    for J := 0 to 2 do
    begin
      Result[I, J] := 0;
      for K := 0 to 2 do Result[I, J] := Result[I, J] + A[I, K] * B[K, J];
    end;
end;

function EulerToMatrix(AX, AY, AZ: Double): TMat3;
var RX, RY, RZ: TMat3; C, S: Double;
begin
  FillChar(RX, SizeOf(RX), 0); FillChar(RY, SizeOf(RY), 0); FillChar(RZ, SizeOf(RZ), 0);
  C := Cos(DegToRad(AX)); S := Sin(DegToRad(AX));
  RX[0, 0] := 1; RX[1, 1] := C; RX[1, 2] := -S; RX[2, 1] := S; RX[2, 2] := C;
  C := Cos(DegToRad(AY)); S := Sin(DegToRad(AY));
  RY[0, 0] := C; RY[0, 2] := S; RY[1, 1] := 1; RY[2, 0] := -S; RY[2, 2] := C;
  C := Cos(DegToRad(AZ)); S := Sin(DegToRad(AZ));
  RZ[0, 0] := C; RZ[0, 1] := -S; RZ[1, 0] := S; RZ[1, 1] := C; RZ[2, 2] := 1;
  Result := MatMul3(RZ, MatMul3(RY, RX));
end;

function CleanAngle(A: Double): Double;
begin
  { arredonda ruido numerico (89.9999999 -> 90) e deixa em -180..180 }
  Result := RoundTo(A, -6);
  while Result > 180 do Result := Result - 360;
  while Result <= -180 do Result := Result + 360;
  if Abs(Result) < 1e-6 then Result := 0;
end;

procedure MatrixToEuler(const M: TMat3; out AX, AY, AZ: Double);
var SY: Double;
begin
  SY := EnsureRange(-M[2, 0], -1, 1);
  AY := ArcSin(SY);
  if Abs(Cos(AY)) > 1e-6 then
  begin
    AX := ArcTan2(M[2, 1], M[2, 2]);
    AZ := ArcTan2(M[1, 0], M[0, 0]);
  end
  else
  begin
    { trava de cardan: fixa Z = 0 }
    AZ := 0;
    AX := ArcTan2(-M[1, 2], M[1, 1]);
  end;
  AX := CleanAngle(RadToDeg(AX));
  AY := CleanAngle(RadToDeg(AY));
  AZ := CleanAngle(RadToDeg(AZ));
end;

function AxisAngle(const Axis: TVec3; AngleRad: Double): TMat3;
var C, S, T, L, X, Y, Z: Double;
begin
  L := Sqrt(Dot(Axis, Axis));
  if L < 1e-12 then
  begin
    FillChar(Result, SizeOf(Result), 0);
    Result[0, 0] := 1; Result[1, 1] := 1; Result[2, 2] := 1;
    Exit;
  end;
  X := Axis.X / L; Y := Axis.Y / L; Z := Axis.Z / L;
  C := Cos(AngleRad); S := Sin(AngleRad); T := 1 - C;
  Result[0, 0] := T * X * X + C;     Result[0, 1] := T * X * Y - S * Z; Result[0, 2] := T * X * Z + S * Y;
  Result[1, 0] := T * X * Y + S * Z; Result[1, 1] := T * Y * Y + C;     Result[1, 2] := T * Y * Z - S * X;
  Result[2, 0] := T * X * Z - S * Y; Result[2, 1] := T * Y * Z + S * X; Result[2, 2] := T * Z * Z + C;
end;

function MatApply(const M: TMat3; const P: TVec3): TVec3;
begin
  Result := Vec3(M[0, 0] * P.X + M[0, 1] * P.Y + M[0, 2] * P.Z,
                 M[1, 0] * P.X + M[1, 1] * P.Y + M[1, 2] * P.Z,
                 M[2, 0] * P.X + M[2, 1] * P.Y + M[2, 2] * P.Z);
end;

{ rotacao que leva a normal unitaria N para (0, 0, -1) }
function AlignDown(const N: TVec3): TMat3;
var D: Double;
begin
  D := -N.Z;   { N . (0,0,-1) }
  if D > 1 - 1e-9 then Result := AxisAngle(Vec3(1, 0, 0), 0)
  else if D < -1 + 1e-9 then Result := AxisAngle(Vec3(1, 0, 0), Pi)
  else Result := AxisAngle(Cross(N, Vec3(0, 0, -1)), ArcCos(EnsureRange(D, -1, 1)));
end;

function Vec3(AX, AY, AZ: Double): TVec3;
begin
  Result.X := AX; Result.Y := AY; Result.Z := AZ;
end;

procedure BoxInclude(var B: TBox3; const P: TVec3);
begin
  if B.Empty then
  begin
    B.Min := P; B.Max := P; B.Empty := False;
    Exit;
  end;
  B.Min.X := Min(B.Min.X, P.X); B.Min.Y := Min(B.Min.Y, P.Y); B.Min.Z := Min(B.Min.Z, P.Z);
  B.Max.X := Max(B.Max.X, P.X); B.Max.Y := Max(B.Max.Y, P.Y); B.Max.Z := Max(B.Max.Z, P.Z);
end;

function MeshBox(M: TMesh): TBox3;
var I: Integer; T: TTriangle;
begin
  Result.Empty := True;
  Result.Min := Vec3(0, 0, 0); Result.Max := Result.Min;
  if M = nil then Exit;
  for I := 0 to M.Count - 1 do
  begin
    T := M.Triangle(I);
    BoxInclude(Result, T.A); BoxInclude(Result, T.B); BoxInclude(Result, T.C);
  end;
end;

{ ---------------- TSliceObject ---------------- }

constructor TSliceObject.Create(ASource: TMesh; const AName, AFile: string);
var B: TBox3;
begin
  inherited Create;
  FSource := ASource;
  FWorld := TMesh.Create;
  Name := AName;
  SourceFile := AFile;
  B := MeshBox(FSource);
  FSourceCenter := Vec3((B.Min.X + B.Max.X) / 2, (B.Min.Y + B.Max.Y) / 2, (B.Min.Z + B.Max.Z) / 2);
  FScaleX := 1; FScaleY := 1; FScaleZ := 1;
  FDirty := True;
  Inc(NextObjectId);
  FId := NextObjectId;
end;

destructor TSliceObject.Destroy;
begin
  FWorld.Free;
  FSource.Free;
  inherited Destroy;
end;

function TSliceObject.Clone: TSliceObject;
var M: TMesh; I: Integer;
begin
  M := TMesh.Create;
  for I := 0 to FSource.Count - 1 do M.Add(FSource.Triangle(I));
  Result := TSliceObject.Create(M, Name, SourceFile);
  Result.FX := FX; Result.FY := FY; Result.FLift := FLift;
  Result.FRotX := FRotX; Result.FRotY := FRotY; Result.FRotZ := FRotZ;
  Result.FScaleX := FScaleX; Result.FScaleY := FScaleY; Result.FScaleZ := FScaleZ;
  Result.FMirrorX := FMirrorX; Result.FMirrorY := FMirrorY; Result.FMirrorZ := FMirrorZ;
  Result.Locked := Locked;
end;

procedure TSliceObject.Changed;
begin
  FDirty := True;
  Inc(FVersion);
  Inc(FShapeVersion);
end;

procedure TSliceObject.SetX(V: Double); begin if V <> FX then begin FX := V; Changed; end; end;
procedure TSliceObject.SetY(V: Double); begin if V <> FY then begin FY := V; Changed; end; end;
procedure TSliceObject.SetLift(V: Double); begin V := Max(0, V); if V <> FLift then begin FLift := V; Changed; end; end;
procedure TSliceObject.SetRotX(V: Double); begin if V <> FRotX then begin FRotX := V; Changed; end; end;
procedure TSliceObject.SetRotY(V: Double); begin if V <> FRotY then begin FRotY := V; Changed; end; end;
procedure TSliceObject.SetRotZ(V: Double); begin if V <> FRotZ then begin FRotZ := V; Changed; end; end;
procedure TSliceObject.SetScaleX(V: Double); begin V := EnsureRange(V, 0.001, 1000); if V <> FScaleX then begin FScaleX := V; Changed; end; end;
procedure TSliceObject.SetScaleY(V: Double); begin V := EnsureRange(V, 0.001, 1000); if V <> FScaleY then begin FScaleY := V; Changed; end; end;
procedure TSliceObject.SetScaleZ(V: Double); begin V := EnsureRange(V, 0.001, 1000); if V <> FScaleZ then begin FScaleZ := V; Changed; end; end;
procedure TSliceObject.SetMirrorX(V: Boolean); begin if V <> FMirrorX then begin FMirrorX := V; Changed; end; end;
procedure TSliceObject.SetMirrorY(V: Boolean); begin if V <> FMirrorY then begin FMirrorY := V; Changed; end; end;
procedure TSliceObject.SetMirrorZ(V: Boolean); begin if V <> FMirrorZ then begin FMirrorZ := V; Changed; end; end;

procedure TSliceObject.SetScaleUniform(S: Double);
begin
  S := EnsureRange(S, 0.001, 1000);
  FScaleX := S; FScaleY := S; FScaleZ := S;
  Changed;
end;

procedure TSliceObject.MoveBy(DX, DY: Double);
var I: Integer; T: TTriangle;
begin
  if Locked or ((DX = 0) and (DY = 0)) then Exit;
  FX := FX + DX; FY := FY + DY;
  Inc(FVersion);
  if FDirty then Exit;
  { translacao pura (arrastar na mesa): desloca o cache, sem refazer rotacoes }
  for I := 0 to FWorld.Count - 1 do
  begin
    T := FWorld.Triangle(I);
    T.A.X := T.A.X + DX; T.A.Y := T.A.Y + DY;
    T.B.X := T.B.X + DX; T.B.Y := T.B.Y + DY;
    T.C.X := T.C.X + DX; T.C.Y := T.C.Y + DY;
    FWorld.SetTriangle(I, T);
  end;
  FWorldBox.Min.X := FWorldBox.Min.X + DX; FWorldBox.Max.X := FWorldBox.Max.X + DX;
  FWorldBox.Min.Y := FWorldBox.Min.Y + DY; FWorldBox.Max.Y := FWorldBox.Max.Y + DY;
end;

{ escala/espelho e rotacao em torno do centro da malha original }
function TSliceObject.TransformPoint(const P: TVec3): TVec3;
var PX, PY, PZ, T, A, SX, SY, SZ: Double;
begin
  SX := FScaleX; if FMirrorX then SX := -SX;
  SY := FScaleY; if FMirrorY then SY := -SY;
  SZ := FScaleZ; if FMirrorZ then SZ := -SZ;
  PX := (P.X - FSourceCenter.X) * SX;
  PY := (P.Y - FSourceCenter.Y) * SY;
  PZ := (P.Z - FSourceCenter.Z) * SZ;
  if FRotX <> 0 then
  begin
    A := DegToRad(FRotX);
    T := PY; PY := T * Cos(A) - PZ * Sin(A); PZ := T * Sin(A) + PZ * Cos(A);
  end;
  if FRotY <> 0 then
  begin
    A := DegToRad(FRotY);
    T := PX; PX := T * Cos(A) + PZ * Sin(A); PZ := -T * Sin(A) + PZ * Cos(A);
  end;
  if FRotZ <> 0 then
  begin
    A := DegToRad(FRotZ);
    T := PX; PX := T * Cos(A) - PY * Sin(A); PY := T * Sin(A) + PY * Cos(A);
  end;
  Result := Vec3(PX, PY, PZ);
end;

procedure TSliceObject.Rebuild;
var I, N, Mirrors: Integer; T, R: TTriangle; Tmp: array of TTriangle; B: TBox3; DX, DY, DZ: Double;
begin
  N := FSource.Count;
  SetLength(Tmp, N);
  Mirrors := Ord(FMirrorX) + Ord(FMirrorY) + Ord(FMirrorZ);
  B.Empty := True;
  for I := 0 to N - 1 do
  begin
    T := FSource.Triangle(I);
    R.A := TransformPoint(T.A);
    if Odd(Mirrors) then
    begin
      R.B := TransformPoint(T.C);
      R.C := TransformPoint(T.B);
    end
    else
    begin
      R.B := TransformPoint(T.B);
      R.C := TransformPoint(T.C);
    end;
    BoxInclude(B, R.A); BoxInclude(B, R.B); BoxInclude(B, R.C);
    Tmp[I] := R;
  end;
  DX := 0; DY := 0; DZ := 0;
  if not B.Empty then
  begin
    DX := FX - (B.Min.X + B.Max.X) / 2;
    DY := FY - (B.Min.Y + B.Max.Y) / 2;
    DZ := FLift - B.Min.Z;
  end;
  FWorld.Clear;
  FWorld.Capacity := N;
  for I := 0 to N - 1 do
  begin
    R := Tmp[I];
    R.A.X := R.A.X + DX; R.A.Y := R.A.Y + DY; R.A.Z := R.A.Z + DZ;
    R.B.X := R.B.X + DX; R.B.Y := R.B.Y + DY; R.B.Z := R.B.Z + DZ;
    R.C.X := R.C.X + DX; R.C.Y := R.C.Y + DY; R.C.Z := R.C.Z + DZ;
    FWorld.Add(R);
  end;
  FWorldBox := B;
  if not B.Empty then
  begin
    FWorldBox.Min := Vec3(B.Min.X + DX, B.Min.Y + DY, B.Min.Z + DZ);
    FWorldBox.Max := Vec3(B.Max.X + DX, B.Max.Y + DY, B.Max.Z + DZ);
  end;
  FDirty := False;
end;

function TSliceObject.GetWorld: TMesh;
begin
  if FDirty then Rebuild;
  Result := FWorld;
end;

function TSliceObject.GetWorldBox: TBox3;
begin
  if FDirty then
  begin
    { caixa sem montar a malha inteira: transforma so os vertices }
    Rebuild;
  end;
  Result := FWorldBox;
end;

function TSliceObject.SourceSize: TVec3;
var B: TBox3;
begin
  B := MeshBox(FSource);
  Result := Vec3(B.Max.X - B.Min.X, B.Max.Y - B.Min.Y, B.Max.Z - B.Min.Z);
end;

function TSliceObject.Size: TVec3;
var B: TBox3;
begin
  B := WorldBox;
  Result := Vec3(B.Max.X - B.Min.X, B.Max.Y - B.Min.Y, B.Max.Z - B.Min.Z);
end;

function TSliceObject.GetState: TTransformState;
begin
  Result.Id := FId;
  Result.X := FX; Result.Y := FY; Result.Lift := FLift;
  Result.RotX := FRotX; Result.RotY := FRotY; Result.RotZ := FRotZ;
  Result.ScaleX := FScaleX; Result.ScaleY := FScaleY; Result.ScaleZ := FScaleZ;
  Result.MirrorX := FMirrorX; Result.MirrorY := FMirrorY; Result.MirrorZ := FMirrorZ;
  Result.Locked := Locked;
end;

procedure TSliceObject.SetState(const S: TTransformState);
begin
  FX := S.X; FY := S.Y; FLift := S.Lift;
  FRotX := S.RotX; FRotY := S.RotY; FRotZ := S.RotZ;
  FScaleX := S.ScaleX; FScaleY := S.ScaleY; FScaleZ := S.ScaleZ;
  FMirrorX := S.MirrorX; FMirrorY := S.MirrorY; FMirrorZ := S.MirrorZ;
  Locked := S.Locked;
  Changed;
end;

procedure TSliceObject.SetRotation(AX, AY, AZ: Double);
begin
  FRotX := CleanAngle(AX); FRotY := CleanAngle(AY); FRotZ := CleanAngle(AZ);
  Changed;
end;

procedure TSliceObject.AlignNormalDown(const N: TVec3);
var M: TMat3; AX, AY, AZ: Double;
begin
  if Dot(N, N) < 1e-12 then Exit;
  { mundo = R * S * p; a nova rotacao e A * R (A leva N para baixo) }
  M := MatMul3(AlignDown(N), EulerToMatrix(FRotX, FRotY, FRotZ));
  MatrixToEuler(M, AX, AY, AZ);
  SetRotation(AX, AY, AZ);
end;

procedure TSliceObject.RotateWorld(Axis: Integer; Deg: Double);
var Ax: TVec3; M: TMat3; AX2, AY2, AZ2: Double;
begin
  case Axis of
    0: Ax := Vec3(1, 0, 0);
    1: Ax := Vec3(0, 1, 0);
  else
    Ax := Vec3(0, 0, 1);
  end;
  M := MatMul3(AxisAngle(Ax, DegToRad(Deg)), EulerToMatrix(FRotX, FRotY, FRotZ));
  MatrixToEuler(M, AX2, AY2, AZ2);
  SetRotation(AX2, AY2, AZ2);
end;

procedure TSliceObject.LayFlatTriangle(Index: Integer);
var W: TMesh;
begin
  W := WorldMesh;
  if (Index < 0) or (Index >= W.Count) then Exit;
  AlignNormalDown(TriNormal(W.Triangle(Index)));
end;

function TSliceObject.ContactArea: Double;
var W: TMesh; I: Integer; T: TTriangle; Z0: Double;
begin
  Result := 0;
  W := WorldMesh;
  Z0 := WorldBox.Min.Z;
  for I := 0 to W.Count - 1 do
  begin
    T := W.Triangle(I);
    if (T.A.Z < Z0 + 0.05) and (T.B.Z < Z0 + 0.05) and (T.C.Z < Z0 + 0.05) and
      (TriNormal(T).Z < -0.98) then
      Result := Result + TriArea(T);
  end;
end;

function TSliceObject.LayFlatAuto: Boolean;
type
  TGroup = record N: TVec3; Area: Double; end;
var
  W: TMesh; I, K, Best, C: Integer; T: TTriangle; N, P: TVec3; A, Z0, Contact, BestContact: Double;
  Map: specialize TDictionary<Int64, Integer>; Groups: array of TGroup; Key: Int64;
  Order: array of Integer; Tmp: Integer; Al: TMat3; Zs: array of Double;
  function Quant(V: Double): Int64; begin Result := Round(V * 60) + 100; end;
begin
  Result := False;
  W := WorldMesh;
  if W.Count = 0 then Exit;
  { agrupa os triangulos pela normal (passo ~1 grau) e soma as areas }
  Map := specialize TDictionary<Int64, Integer>.Create;
  try
    for I := 0 to W.Count - 1 do
    begin
      T := W.Triangle(I);
      N := TriNormal(T);
      if Dot(N, N) < 0.5 then Continue;
      Key := (Quant(N.X) * 1000 + Quant(N.Y)) * 1000 + Quant(N.Z);
      A := TriArea(T);
      if Map.TryGetValue(Key, K) then
      begin
        Groups[K].N := Vec3(Groups[K].N.X + N.X * A, Groups[K].N.Y + N.Y * A, Groups[K].N.Z + N.Z * A);
        Groups[K].Area := Groups[K].Area + A;
      end
      else
      begin
        K := Length(Groups);
        SetLength(Groups, K + 1);
        Groups[K].N := Vec3(N.X * A, N.Y * A, N.Z * A);
        Groups[K].Area := A;
        Map.Add(Key, K);
      end;
    end;
  finally
    Map.Free;
  end;
  if Length(Groups) = 0 then Exit;
  { as 12 maiores areas planas sao candidatas; vence a que da mais apoio na mesa }
  SetLength(Order, Length(Groups));
  for I := 0 to High(Order) do Order[I] := I;
  for I := 0 to Min(11, High(Order)) do
    for K := I + 1 to High(Order) do
      if Groups[Order[K]].Area > Groups[Order[I]].Area then
      begin
        Tmp := Order[I]; Order[I] := Order[K]; Order[K] := Tmp;
      end;
  SetLength(Zs, W.Count * 3);
  Best := -1;
  BestContact := ContactArea * 1.02;   { so troca se melhorar de verdade }
  for C := 0 to Min(11, High(Order)) do
  begin
    N := Groups[Order[C]].N;
    A := Sqrt(Dot(N, N));
    if A < 1e-12 then Continue;
    N := Vec3(N.X / A, N.Y / A, N.Z / A);
    Al := AlignDown(N);
    Z0 := MaxDouble;
    for I := 0 to W.Count - 1 do
    begin
      T := W.Triangle(I);
      P := MatApply(Al, T.A); Zs[I * 3] := P.Z;
      P := MatApply(Al, T.B); Zs[I * 3 + 1] := P.Z;
      P := MatApply(Al, T.C); Zs[I * 3 + 2] := P.Z;
      Z0 := Min(Z0, Min(Zs[I * 3], Min(Zs[I * 3 + 1], Zs[I * 3 + 2])));
    end;
    Contact := 0;
    for I := 0 to W.Count - 1 do
      if (Zs[I * 3] < Z0 + 0.05) and (Zs[I * 3 + 1] < Z0 + 0.05) and (Zs[I * 3 + 2] < Z0 + 0.05) then
      begin
        T := W.Triangle(I);
        if Dot(TriNormal(T), N) > 0.98 then Contact := Contact + TriArea(T);
      end;
    if Contact > BestContact then
    begin
      BestContact := Contact;
      Best := Order[C];
    end;
  end;
  if Best < 0 then Exit;
  N := Groups[Best].N;
  A := Sqrt(Dot(N, N));
  AlignNormalDown(Vec3(N.X / A, N.Y / A, N.Z / A));
  Result := True;
end;

{ ---------------- TSliceScene ---------------- }

constructor TSliceScene.Create;
begin
  inherited Create;
  FItems := TObjectList.Create(True);
  BedX := 220; BedY := 220; BedZ := 250;
  Spacing := 4;
end;

destructor TSliceScene.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TSliceScene.Touch;
begin
  Inc(FVersion);
end;

procedure TSliceScene.Clear;
begin
  FItems.Clear;
  SetLength(FPillars, 0);
  SetLength(FBlockers, 0);
  Touch;
end;

function TSliceScene.Count: Integer;
begin
  Result := FItems.Count;
end;

function TSliceScene.GetItem(I: Integer): TSliceObject;
begin
  Result := TSliceObject(FItems[I]);
end;

function TSliceScene.IndexOf(O: TSliceObject): Integer;
begin
  Result := FItems.IndexOf(O);
end;

function BoxesOverlap(const A, B: TBox3; Gap: Double): Boolean;
begin
  Result := not ((A.Max.X + Gap <= B.Min.X) or (B.Max.X + Gap <= A.Min.X) or
    (A.Max.Y + Gap <= B.Min.Y) or (B.Max.Y + Gap <= A.Min.Y));
end;

function TSliceScene.FindSpotAmong(SX, SY: Double; const Obstacles: array of TBox3; out PX, PY: Double): Boolean;
var Ring, K, Steps: Integer; Step, CX, CY: Double;

  function TrySpot(X0, Y0: Double): Boolean;
  var J: Integer; Cand: TBox3;
  begin
    Result := False;
    Cand.Empty := False;
    Cand.Min := Vec3(X0 - SX / 2, Y0 - SY / 2, 0);
    Cand.Max := Vec3(X0 + SX / 2, Y0 + SY / 2, 0);
    if (Cand.Min.X < 0) or (Cand.Min.Y < 0) or (Cand.Max.X > BedX) or (Cand.Max.Y > BedY) then Exit;
    for J := 0 to High(Obstacles) do
      if (not Obstacles[J].Empty) and BoxesOverlap(Cand, Obstacles[J], Spacing) then Exit;
    PX := X0; PY := Y0;
    Result := True;
  end;

begin
  CX := BedX / 2; CY := BedY / 2;
  PX := CX; PY := CY;
  if TrySpot(CX, CY) then Exit(True);
  { aneis quadrados em volta do centro, passo de 2 mm }
  Step := 2;
  Steps := Ceil(Max(BedX, BedY) / Step);
  for Ring := 1 to Steps do
    for K := -Ring to Ring do
      if TrySpot(CX + K * Step, CY - Ring * Step) or TrySpot(CX + K * Step, CY + Ring * Step) or
        TrySpot(CX - Ring * Step, CY + K * Step) or TrySpot(CX + Ring * Step, CY + K * Step) then
        Exit(True);
  { sem lugar: fica no centro e a validacao avisa }
  PX := CX; PY := CY;
  Result := False;
end;

function TSliceScene.FindFreeSpot(SX, SY: Double; Ignore: Integer; out PX, PY: Double): Boolean;
var Obs: array of TBox3; I: Integer;
begin
  SetLength(Obs, Count);
  for I := 0 to Count - 1 do
    if I = Ignore then Obs[I].Empty := True else Obs[I] := Items[I].WorldBox;
  Result := FindSpotAmong(SX, SY, Obs, PX, PY);
end;

function TSliceScene.FindById(AId: Integer): TSliceObject;
var I: Integer;
begin
  for I := 0 to Count - 1 do
    if Items[I].Id = AId then Exit(Items[I]);
  Result := nil;
end;

function TSliceScene.Arrange: Boolean;
var
  Order: array of Integer; Obs: array of TBox3; I, K, Tmp, N: Integer; Sz: TVec3; PX, PY: Double;
  function Area(Idx: Integer): Double;
  var S: TVec3;
  begin
    S := Items[Idx].Size;
    Result := S.X * S.Y;
  end;
begin
  Result := True;
  { travadas ficam onde estao e viram obstaculo }
  N := 0;
  SetLength(Obs, Count);
  for I := 0 to Count - 1 do
    if Items[I].Locked then
    begin
      Obs[N] := Items[I].WorldBox;
      Inc(N);
    end;
  SetLength(Order, 0);
  for I := 0 to Count - 1 do
    if not Items[I].Locked then
    begin
      SetLength(Order, Length(Order) + 1);
      Order[High(Order)] := I;
    end;
  for I := 0 to High(Order) do
    for K := I + 1 to High(Order) do
      if Area(Order[K]) > Area(Order[I]) then
      begin
        Tmp := Order[I]; Order[I] := Order[K]; Order[K] := Tmp;
      end;
  for I := 0 to High(Order) do
  begin
    Sz := Items[Order[I]].Size;
    if not FindSpotAmong(Sz.X, Sz.Y, Copy(Obs, 0, N), PX, PY) then Result := False;
    Items[Order[I]].X := PX;
    Items[Order[I]].Y := PY;
    Obs[N] := Items[Order[I]].WorldBox;
    Inc(N);
  end;
  Touch;
end;

function TSliceScene.DuplicateN(I, N: Integer): Integer;
var K: Integer; O: TSliceObject; S: TVec3; PX, PY: Double;
begin
  Result := 0;
  for K := 1 to N do
  begin
    S := Items[I].Size;
    if not FindFreeSpot(S.X, S.Y, -1, PX, PY) then Break;
    O := Items[I].Clone;
    O.Name := Items[I].Name;
    O.Locked := False;
    O.X := PX; O.Y := PY;
    FItems.Add(O);
    Inc(Result);
  end;
  Touch;
end;

function TSliceScene.Capture: TSceneState;
var I: Integer;
begin
  SetLength(Result, Count);
  for I := 0 to Count - 1 do Result[I] := Items[I].GetState;
end;

procedure TSliceScene.Apply(const St: TSceneState);
var I: Integer; O: TSliceObject;
begin
  for I := 0 to High(St) do
  begin
    O := FindById(St[I].Id);
    if O <> nil then O.SetState(St[I]);
  end;
  Touch;
end;

procedure TSliceScene.PushUndo;
const MaxHistory = 60;
begin
  if Length(FUndo) >= MaxHistory then System.Delete(FUndo, 0, 1);
  SetLength(FUndo, Length(FUndo) + 1);
  FUndo[High(FUndo)] := Capture;
  SetLength(FRedo, 0);
end;

function TSliceScene.Undo: Boolean;
begin
  Result := Length(FUndo) > 0;
  if not Result then Exit;
  SetLength(FRedo, Length(FRedo) + 1);
  FRedo[High(FRedo)] := Capture;
  Apply(FUndo[High(FUndo)]);
  SetLength(FUndo, Length(FUndo) - 1);
end;

function TSliceScene.Redo: Boolean;
begin
  Result := Length(FRedo) > 0;
  if not Result then Exit;
  SetLength(FUndo, Length(FUndo) + 1);
  FUndo[High(FUndo)] := Capture;
  Apply(FRedo[High(FRedo)]);
  SetLength(FRedo, Length(FRedo) - 1);
end;

function TSliceScene.CanUndo: Boolean;
begin
  Result := Length(FUndo) > 0;
end;

function TSliceScene.CanRedo: Boolean;
begin
  Result := Length(FRedo) > 0;
end;

procedure TSliceScene.ClearHistory;
begin
  SetLength(FUndo, 0);
  SetLength(FRedo, 0);
end;

procedure TSliceScene.AddPillar(O: TSliceObject; X, Y, ZTop, Diameter: Double);
var N: Integer;
begin
  if O = nil then Exit;
  N := Length(FPillars);
  SetLength(FPillars, N + 1);
  FPillars[N].ObjId := O.Id;
  FPillars[N].Shape := O.ShapeVersion;
  FPillars[N].DX := X - O.X;
  FPillars[N].DY := Y - O.Y;
  FPillars[N].ZTop := ZTop;
  FPillars[N].Diameter := Diameter;
  Touch;
end;

procedure TSliceScene.ClearPillars;
begin
  SetLength(FPillars, 0);
  Touch;
end;

function TSliceScene.PillarCount: Integer;
begin
  Result := Length(FPillars);
end;

function TSliceScene.Pillar(I: Integer): TScenePillar;
begin
  Result := FPillars[I];
end;

function TSliceScene.PillarAbs(I: Integer; out X, Y, ZTop, Diameter: Double): Boolean;
var O: TSliceObject;
begin
  X := 0; Y := 0; ZTop := 0; Diameter := 0;
  O := FindById(FPillars[I].ObjId);
  Result := (O <> nil) and (O.ShapeVersion = FPillars[I].Shape);
  if not Result then Exit;
  X := O.X + FPillars[I].DX;
  Y := O.Y + FPillars[I].DY;
  ZTop := FPillars[I].ZTop;
  Diameter := FPillars[I].Diameter;
end;

function TSliceScene.RemoveInvalidPillars: Integer;
var I, K: Integer; X, Y, Z, D: Double;
begin
  Result := 0;
  K := 0;
  for I := 0 to High(FPillars) do
    if PillarAbs(I, X, Y, Z, D) then
    begin
      FPillars[K] := FPillars[I];
      Inc(K);
    end
    else Inc(Result);
  SetLength(FPillars, K);
  if Result > 0 then Touch;
end;

function TSliceScene.AddBlocker(const B: TSceneBlocker): Integer;
begin
  Result := Length(FBlockers);
  SetLength(FBlockers, Result + 1);
  FBlockers[Result] := B;
  Touch;
end;

procedure TSliceScene.SetBlocker(I: Integer; const B: TSceneBlocker);
begin
  FBlockers[I] := B;
  Touch;
end;

procedure TSliceScene.DeleteBlocker(I: Integer);
begin
  System.Delete(FBlockers, I, 1);
  Touch;
end;

function TSliceScene.BlockerCount: Integer;
begin
  Result := Length(FBlockers);
end;

function TSliceScene.Blocker(I: Integer): TSceneBlocker;
begin
  Result := FBlockers[I];
end;

function TSliceScene.AddObject(O: TSliceObject; FindPlace: Boolean): TSliceObject;
var S: TVec3; PX, PY: Double;
begin
  Result := O;
  if FindPlace then
  begin
    O.X := BedX / 2; O.Y := BedY / 2;
    S := O.Size;
    FindFreeSpot(S.X, S.Y, -1, PX, PY);
    O.X := PX; O.Y := PY;
  end;
  FItems.Add(O);
  Touch;
end;

function TSliceScene.Add(AMesh: TMesh; const AName, AFile: string): TSliceObject;
begin
  Result := AddObject(TSliceObject.Create(AMesh, AName, AFile), True);
end;

procedure TSliceScene.Delete(I: Integer);
begin
  FItems.Delete(I);
  Touch;
end;

procedure TSliceScene.DeleteSelected;
var I: Integer;
begin
  for I := Count - 1 downto 0 do
    if Items[I].Selected then FItems.Delete(I);
  Touch;
end;

function TSliceScene.Duplicate(I: Integer): TSliceObject;
begin
  Result := Items[I].Clone;
  Result.Name := Items[I].Name;
  AddObject(Result, True);
end;

procedure TSliceScene.SelectOnly(I: Integer);
var J: Integer;
begin
  for J := 0 to Count - 1 do Items[J].Selected := J = I;
  Touch;
end;

procedure TSliceScene.ToggleSelect(I: Integer);
begin
  if (I < 0) or (I >= Count) then Exit;
  Items[I].Selected := not Items[I].Selected;
  Touch;
end;

function TSliceScene.SelectedCount: Integer;
var I: Integer;
begin
  Result := 0;
  for I := 0 to Count - 1 do if Items[I].Selected then Inc(Result);
end;

function TSliceScene.FirstSelected: Integer;
var I: Integer;
begin
  for I := 0 to Count - 1 do if Items[I].Selected then Exit(I);
  Result := -1;
end;

procedure TSliceScene.CenterObject(I: Integer);
begin
  if (I < 0) or (I >= Count) or Items[I].Locked then Exit;
  Items[I].X := BedX / 2;
  Items[I].Y := BedY / 2;
  Touch;
end;

function TSliceScene.Overlaps(I, J: Integer): Boolean;
begin
  Result := BoxesOverlap(Items[I].WorldBox, Items[J].WorldBox, 0);
end;

function TSliceScene.Inside(I: Integer): Boolean;
var B: TBox3;
begin
  B := Items[I].WorldBox;
  Result := B.Empty or ((B.Min.X >= -1e-6) and (B.Min.Y >= -1e-6) and (B.Max.X <= BedX + 1e-6) and
    (B.Max.Y <= BedY + 1e-6) and (B.Max.Z <= BedZ + 1e-6));
end;

function TSliceScene.Validate(Errors: TStrings): Boolean;
var I, J: Integer; B: TBox3; FS: TFormatSettings;
begin
  FS := DefaultFormatSettings; FS.DecimalSeparator := '.';
  if Count = 0 then Errors.Add('Abra um modelo STL ou 3MF.');
  for I := 0 to Count - 1 do
  begin
    B := Items[I].WorldBox;
    if not Inside(I) then
    begin
      if B.Max.Z > BedZ + 1e-6 then
        Errors.Add(Format('%s: tem %.1f mm de altura; a impressora vai ate %.0f mm.',
          [Items[I].Name, B.Max.Z, BedZ], FS))
      else
        Errors.Add(Format('%s: sai da mesa (X %.1f..%.1f, Y %.1f..%.1f; mesa %.0f x %.0f mm).',
          [Items[I].Name, B.Min.X, B.Max.X, B.Min.Y, B.Max.Y, BedX, BedY], FS));
    end;
    for J := I + 1 to Count - 1 do
      if Overlaps(I, J) then
        Errors.Add(Format('%s e %s se sobrepoem na mesa.', [Items[I].Name, Items[J].Name]));
  end;
  Result := Errors.Count = 0;
end;

procedure TSliceScene.MergedMesh(Dest: TMesh);
var I, K: Integer; M: TMesh;
begin
  Dest.Clear;
  for I := 0 to Count - 1 do
  begin
    M := Items[I].WorldMesh;
    for K := 0 to M.Count - 1 do Dest.Add(M.Triangle(K));
  end;
end;

function TSliceScene.Bounds: TBox3;
var I: Integer; B: TBox3;
begin
  Result.Empty := True;
  Result.Min := Vec3(0, 0, 0); Result.Max := Result.Min;
  for I := 0 to Count - 1 do
  begin
    B := Items[I].WorldBox;
    if B.Empty then Continue;
    BoxInclude(Result, B.Min);
    BoxInclude(Result, B.Max);
  end;
end;

function TSliceScene.TriangleCount: Integer;
var I: Integer;
begin
  Result := 0;
  for I := 0 to Count - 1 do Inc(Result, Items[I].Source.Count);
end;

end.
