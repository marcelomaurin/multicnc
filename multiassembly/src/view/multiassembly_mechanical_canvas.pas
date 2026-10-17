unit multiassembly_mechanical_canvas;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Math, LCLType, Forms,
  multiassembly_types, multiassembly_project, multiassembly_solver, multiassembly_geometry;

type
  TAssemblyViewMode = (avm3DOrbit, avmTop, avmFront, avmSide);

  TComponentSelectEvent = procedure(Sender: TObject; const ComponentID: string) of object;
  TKinematicMoveEvent = procedure(Sender: TObject; const ComponentID: string) of object;

  { cache da malha 3D de cada componente }
  TMeshCacheItem = record
    ID: string;
    Sig: string;
    Mesh: TAssemblyMesh;
  end;

  { transformacao local -> mundo de um componente }
  TCompXform = record
    Pos, Center, Scale, GMin: TAssemblyVec3;
    R: array[0..2, 0..2] of Double;
  end;

  { face projetada pronta para desenho (algoritmo do pintor) }
  TDrawFace = record
    Start, Count: Integer; // fatia de FPointBuf
    Depth: Double;
    Fill, Pen: TColor;
  end;

  TMechanicalAssemblyCanvas = class(TCustomControl)
  private
    FProject: TAssemblyProject;
    FSolver: TKinematicSolver;
    FSelectedID: string;
    FViewMode: TAssemblyViewMode;

    // Camera 3D Orbital Verdadeira
    FAzimuth: Double;    // Angulo horizontal (graus, 0..360)
    FElevation: Double; // Angulo vertical/pitch (graus, -89..+89)
    FScale: Double;     // Fator de escala/zoom
    FPanX, FPanY: Double;
    FTargetCenter: TAssemblyVec3;

    // Modos de interacao com mouse
    FOrbiting: Boolean;
    FPanning: Boolean;
    FDraggingPart: Boolean;
    FDragPartID: string;
    FDragStartX, FDragStartY: Integer;
    FDragMouseX, FDragMouseY: Integer;
    FInitialPanX, FInitialPanY: Double;
    FInitialAzimuth, FInitialElevation: Double;

    FActiveStep: Integer; // -1 = todas, 0..N = destacar etapa
    FShowDOFArrows: Boolean;
    FShowMateLines: Boolean;
    FShowGrid: Boolean;
    FShowLabels: Boolean;
    FOnSelect: TComponentSelectEvent;
    FOnKinematicMove: TKinematicMoveEvent;

    // Renderizacao realista
    FMeshCache: array of TMeshCacheItem;
    FPointBuf: array of TPoint;
    FPointCount: Integer;
    FDrawFaces: array of TDrawFace;
    FDrawCount: Integer;
    FCosAz, FSinAz, FCosEl, FSinEl: Double;

    procedure UpdateCameraTrig;
    function CameraDir(const V: TAssemblyVec3): TAssemblyVec3;
    function MeshIndexFor(const C: TAssemblyComponent): Integer;
    procedure MakeXform(const C: TAssemblyComponent; const Pos, Rot: TAssemblyVec3; const M: TAssemblyMesh;
      out T: TCompXform);
    function XformPoint(const T: TCompXform; const V: TAssemblyVec3): TAssemblyVec3;
    function XformNormal(const T: TCompXform; const N: TAssemblyVec3): TAssemblyVec3;
    procedure ComponentCorners(const C: TAssemblyComponent; const Pos, Rot: TAssemblyVec3;
      out Corners: array of TAssemblyVec3);
    function ComponentRotation(const C: TAssemblyComponent): TAssemblyVec3;
    procedure CollectComponentFaces(const C: TAssemblyComponent; const Pos, Rot: TAssemblyVec3;
      IsSelected, HasCollision, InCurrentStep: Boolean);
    procedure SortDrawFaces;
    procedure DrawSelectionBox(const C: TAssemblyComponent; const Pos, Rot: TAssemblyVec3);
    procedure DrawComponentLabel(const C: TAssemblyComponent; const Pos, Rot: TAssemblyVec3; const LabelStr: string);
    procedure ProjectToScreen(X, Y, Z: Double; out SX, SY: Integer; out Depth: Double); overload;
    procedure ProjectToScreen(X, Y, Z: Double; out SX, SY: Integer); overload;
    function HitTest(SX, SY: Integer): string;
    function GetStepComponents(StepIdx: Integer): TStringList;
    function IsPartColliding(const CompID: string): Boolean;
    procedure Draw3DTrihedron;
    procedure Draw3DGrid;
    procedure DrawDOFArrows(const CompID: string; const Pos, Size: TAssemblyVec3; const DOF: TComponentDOF);
    procedure DrawArrow(X0, Y0, Z0, DX, DY, DZ: Double; AColor: TColor; const ALabel: string);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure FitToView;
    procedure ZoomIn;
    procedure ZoomOut;
    procedure SetViewMode(Mode: TAssemblyViewMode);
    procedure SetCameraPreset(AzimuthDeg, ElevationDeg: Double);
    procedure ClearMeshCache;

    property Project: TAssemblyProject read FProject write FProject;
    property Solver: TKinematicSolver read FSolver write FSolver;
    property SelectedID: string read FSelectedID write FSelectedID;
    property ViewMode: TAssemblyViewMode read FViewMode write SetViewMode;
    property Azimuth: Double read FAzimuth write FAzimuth;
    property Elevation: Double read FElevation write FElevation;
    property ActiveStep: Integer read FActiveStep write FActiveStep;
    property Scale: Double read FScale write FScale;
    property ShowDOFArrows: Boolean read FShowDOFArrows write FShowDOFArrows;
    property ShowMateLines: Boolean read FShowMateLines write FShowMateLines;
    property ShowGrid: Boolean read FShowGrid write FShowGrid;
    property ShowLabels: Boolean read FShowLabels write FShowLabels;
    property OnSelectComponent: TComponentSelectEvent read FOnSelect write FOnSelect;
    property OnKinematicMove: TKinematicMoveEvent read FOnKinematicMove write FOnKinematicMove;
  end;

implementation

constructor TMechanicalAssemblyCanvas.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque, csDoubleClicks];
  DoubleBuffered := True;
  FAzimuth := 45.0;    // 3D Isometrico angular padrao
  FElevation := 28.0;  // 3D Elevacao angular padrao
  FScale := 2.5;
  FPanX := 0;
  FPanY := 0;
  FTargetCenter := Vec3(80, 50, 20);
  FViewMode := avm3DOrbit;
  FActiveStep := -1;
  FShowDOFArrows := True;
  FShowMateLines := True;
  FShowGrid := True;
  FShowLabels := True;
  FOrbiting := False;
  FPanning := False;
  FDraggingPart := False;
  FDragPartID := '';
  Cursor := crCross;
end;

destructor TMechanicalAssemblyCanvas.Destroy;
begin
  inherited Destroy;
end;

procedure TMechanicalAssemblyCanvas.SetViewMode(Mode: TAssemblyViewMode);
begin
  FViewMode := Mode;
  case Mode of
    avm3DOrbit: SetCameraPreset(45.0, 28.0);
    avmTop:     SetCameraPreset(0.0, 89.9);  // Vista Superior (X-Y)
    avmFront:   SetCameraPreset(0.0, 0.0);   // Vista Frontal (X-Z)
    avmSide:    SetCameraPreset(90.0, 0.0);  // Vista Lateral (Y-Z)
  end;
  FitToView;
  Invalidate;
end;

procedure TMechanicalAssemblyCanvas.SetCameraPreset(AzimuthDeg, ElevationDeg: Double);
begin
  FAzimuth := AzimuthDeg;
  FElevation := EnsureRange(ElevationDeg, -89.0, 89.0);
  Invalidate;
end;

procedure TMechanicalAssemblyCanvas.Resize;
begin
  inherited Resize;
  if (FPanX = 0) and (FPanY = 0) and (Width > 50) and (Height > 50) then
    FitToView;
end;

procedure TMechanicalAssemblyCanvas.ProjectToScreen(X, Y, Z: Double; out SX, SY: Integer; out Depth: Double);
var
  RadAz, RadEl: Double;
  CosAz, SinAz, CosEl, SinEl: Double;
  DX, DY, DZ: Double;
  X1, Y1, Z1: Double;
  X2, Y2, Z2: Double;
  CX, CY: Double;
begin
  RadAz := DegToRad(FAzimuth);
  RadEl := DegToRad(FElevation);

  CosAz := Cos(RadAz);
  SinAz := Sin(RadAz);
  CosEl := Cos(RadEl);
  SinEl := Sin(RadEl);

  // Vetor relativo ao centro do modelo
  DX := X - FTargetCenter.X;
  DY := Y - FTargetCenter.Y;
  DZ := Z - FTargetCenter.Z;

  // 1. Rotacao em torno do eixo Z (Azimute)
  X1 := DX * CosAz - DY * SinAz;
  Y1 := DX * SinAz + DY * CosAz;
  Z1 := DZ;

  // 2. Rotacao em torno do eixo horizontal da camera (Elevacao/Pitch)
  X2 := X1;
  Y2 := Y1 * SinEl + Z1 * CosEl;  // Direcao vertical na tela
  Z2 := Y1 * CosEl - Z1 * SinEl;  // Profundidade (Depth) para ordenacao 3D

  CX := Width * 0.5 + FPanX;
  CY := Height * 0.5 + FPanY;

  SX := Round(CX + X2 * FScale);
  SY := Round(CY - Y2 * FScale);
  Depth := Z2;
end;

procedure TMechanicalAssemblyCanvas.ProjectToScreen(X, Y, Z: Double; out SX, SY: Integer);
var
  D: Double;
begin
  ProjectToScreen(X, Y, Z, SX, SY, D);
end;

function TMechanicalAssemblyCanvas.GetStepComponents(StepIdx: Integer): TStringList;
var
  I, J, MaxStep: Integer;
begin
  Result := TStringList.Create;
  if (FProject = nil) or (StepIdx < 0) then Exit;
  MaxStep := Min(StepIdx, FProject.StepCount - 1);
  for I := 0 to MaxStep do
    for J := 0 to High(FProject.Step(I).ComponentIDs) do
      if Result.IndexOf(FProject.Step(I).ComponentIDs[J]) < 0 then
        Result.Add(FProject.Step(I).ComponentIDs[J]);
end;

function TMechanicalAssemblyCanvas.IsPartColliding(const CompID: string): Boolean;
var
  I: Integer;
  Col: TCollisionItem;
begin
  Result := False;
  if FSolver = nil then Exit;
  for I := 0 to FSolver.CollisionCount - 1 do
  begin
    Col := FSolver.Collision(I);
    if SameText(Col.CompA, CompID) or SameText(Col.CompB, CompID) then
      Exit(True);
  end;
end;

procedure TMechanicalAssemblyCanvas.DrawArrow(X0, Y0, Z0, DX, DY, DZ: Double; AColor: TColor; const ALabel: string);
var
  P1, P2: TPoint;
begin
  ProjectToScreen(X0, Y0, Z0, P1.X, P1.Y);
  ProjectToScreen(X0 + DX, Y0 + DY, Z0 + DZ, P2.X, P2.Y);

  Canvas.Pen.Color := AColor;
  Canvas.Pen.Width := 3;
  Canvas.Line(P1.X, P1.Y, P2.X, P2.Y);

  Canvas.Brush.Color := AColor;
  Canvas.Ellipse(P2.X - 4, P2.Y - 4, P2.X + 4, P2.Y + 4);

  if ALabel <> '' then
  begin
    Canvas.Font.Size := 8;
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := AColor;
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(P2.X + 6, P2.Y - 6, ALabel);
    Canvas.Brush.Style := bsSolid;
  end;
end;

procedure TMechanicalAssemblyCanvas.DrawDOFArrows(const CompID: string; const Pos, Size: TAssemblyVec3; const DOF: TComponentDOF);
var
  CX, CY, CZ, Span: Double;
begin
  if not FShowDOFArrows or (DOF.Status = adsFixed) then Exit;

  CX := Pos.X + Size.X * 0.5;
  CY := Pos.Y + Size.Y * 0.5;
  CZ := Pos.Z + Size.Z * 0.5;
  Span := Max(35.0, Max(Size.X, Max(Size.Y, Size.Z)) * 0.75);

  if DOF.Tx then
  begin
    DrawArrow(CX, CY, CZ,  Span, 0, 0, $4040FF, '+X');
    DrawArrow(CX, CY, CZ, -Span, 0, 0, $4040FF, '-X');
  end;

  if DOF.Ty then
  begin
    DrawArrow(CX, CY, CZ, 0,  Span, 0, $40E040, '+Y');
    DrawArrow(CX, CY, CZ, 0, -Span, 0, $40E040, '-Y');
  end;

  if DOF.Tz then
  begin
    DrawArrow(CX, CY, CZ, 0, 0,  Span, $FFA030, '+Z');
    DrawArrow(CX, CY, CZ, 0, 0, -Span, $FFA030, '-Z');
  end;
end;

procedure TMechanicalAssemblyCanvas.Draw3DTrihedron;
var
  OX, OY: Integer;
  RadAz, RadEl: Double;
  CosAz, SinAz, CosEl, SinEl: Double;
  Len: Double;
  X1, Y1, Z1: Double;
  X2, Y2: Double;
  PX, PY: Integer;
begin
  OX := 56;
  OY := Height - 56;
  Len := 34.0;

  RadAz := DegToRad(FAzimuth);
  RadEl := DegToRad(FElevation);
  CosAz := Cos(RadAz); SinAz := Sin(RadAz);
  CosEl := Cos(RadEl); SinEl := Sin(RadEl);

  Canvas.Brush.Color := $181822;
  Canvas.Pen.Color := $38384C;
  Canvas.Pen.Width := 1;
  Canvas.RoundRect(OX - 42, OY - 42, OX + 46, OY + 46, 8, 8);

  // Eixo X (Vermelho)
  X1 := Len * CosAz; Y1 := Len * SinAz; Z1 := 0;
  X2 := X1; Y2 := Y1 * SinEl + Z1 * CosEl;
  PX := Round(OX + X2); PY := Round(OY - Y2);
  Canvas.Pen.Color := $4040FF; Canvas.Pen.Width := 2;
  Canvas.Line(OX, OY, PX, PY);
  Canvas.Font.Size := 8; Canvas.Font.Style := [fsBold]; Canvas.Font.Color := $4040FF;
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(PX + 2, PY - 6, 'X');

  // Eixo Y (Verde)
  X1 := -Len * SinAz; Y1 := Len * CosAz; Z1 := 0;
  X2 := X1; Y2 := Y1 * SinEl + Z1 * CosEl;
  PX := Round(OX + X2); PY := Round(OY - Y2);
  Canvas.Pen.Color := $40E040;
  Canvas.Line(OX, OY, PX, PY);
  Canvas.Font.Color := $40E040;
  Canvas.TextOut(PX + 2, PY - 6, 'Y');

  // Eixo Z (Azul)
  X1 := 0; Y1 := 0; Z1 := Len;
  X2 := X1; Y2 := Y1 * SinEl + Z1 * CosEl;
  PX := Round(OX + X2); PY := Round(OY - Y2);
  Canvas.Pen.Color := $FFA030;
  Canvas.Line(OX, OY, PX, PY);
  Canvas.Font.Color := $FFA030;
  Canvas.TextOut(PX + 2, PY - 6, 'Z');

  Canvas.Brush.Style := bsSolid;
end;

procedure TMechanicalAssemblyCanvas.Draw3DGrid;
var
  GX, GY, GSize: Integer;
  P1, P2: TPoint;
begin
  if not FShowGrid then Exit;
  Canvas.Pen.Color := $282836;
  Canvas.Pen.Width := 1;
  GSize := 20;

  for GX := -10 to 10 do
  begin
    ProjectToScreen(GX * GSize, -10 * GSize, 0, P1.X, P1.Y);
    ProjectToScreen(GX * GSize,  10 * GSize, 0, P2.X, P2.Y);
    Canvas.Line(P1.X, P1.Y, P2.X, P2.Y);
  end;

  for GY := -10 to 10 do
  begin
    ProjectToScreen(-10 * GSize, GY * GSize, 0, P1.X, P1.Y);
    ProjectToScreen( 10 * GSize, GY * GSize, 0, P2.X, P2.Y);
    Canvas.Line(P1.X, P1.Y, P2.X, P2.Y);
  end;
end;

{ ------------------------------------------------------- renderizacao 3D }

procedure TMechanicalAssemblyCanvas.ClearMeshCache;
begin
  SetLength(FMeshCache, 0);
  Invalidate;
end;

procedure TMechanicalAssemblyCanvas.UpdateCameraTrig;
begin
  FCosAz := Cos(DegToRad(FAzimuth));
  FSinAz := Sin(DegToRad(FAzimuth));
  FCosEl := Cos(DegToRad(FElevation));
  FSinEl := Sin(DegToRad(FElevation));
end;

{ direcao no espaco da camera: X direita, Y para cima, Z profundidade (para dentro da tela) }
function TMechanicalAssemblyCanvas.CameraDir(const V: TAssemblyVec3): TAssemblyVec3;
var
  X1, Y1: Double;
begin
  X1 := V.X * FCosAz - V.Y * FSinAz;
  Y1 := V.X * FSinAz + V.Y * FCosAz;
  Result.X := X1;
  Result.Y := Y1 * FSinEl + V.Z * FCosEl;
  Result.Z := Y1 * FCosEl - V.Z * FSinEl;
end;

function TMechanicalAssemblyCanvas.MeshIndexFor(const C: TAssemblyComponent): Integer;
var
  Sig: string;
  I: Integer;
  G: TAssemblyGeometry;
begin
  Sig := Format('%s|%d|%d|%d|%.3f|%.3f|%.3f', [C.SourceRef, Ord(C.Kind), Length(C.Geometry), C.Color,
    C.Size.X, C.Size.Y, C.Size.Z]);
  if Length(C.Geometry) > 0 then
    Sig := Sig + Format('|%.3f|%.3f|%.3f', [C.Geometry[0].At.X, C.Geometry[0].At.Y, C.Geometry[0].At.Z]);
  for I := 0 to High(FMeshCache) do
    if (FMeshCache[I].ID = C.ID) then
    begin
      if FMeshCache[I].Sig <> Sig then
      begin
        G := ComponentGeometry(C);
        BuildMesh(G, FMeshCache[I].Mesh);
        FMeshCache[I].Sig := Sig;
      end;
      Exit(I);
    end;
  I := Length(FMeshCache);
  SetLength(FMeshCache, I + 1);
  FMeshCache[I].ID := C.ID;
  FMeshCache[I].Sig := Sig;
  G := ComponentGeometry(C);
  BuildMesh(G, FMeshCache[I].Mesh);
  Result := I;
end;

function TMechanicalAssemblyCanvas.ComponentRotation(const C: TAssemblyComponent): TAssemblyVec3;
begin
  if FSolver <> nil then
    Result := FSolver.GetSolvedRotation(C.ID)
  else
    Result := C.Rotation;
end;

procedure TMechanicalAssemblyCanvas.MakeXform(const C: TAssemblyComponent; const Pos, Rot: TAssemblyVec3;
  const M: TAssemblyMesh; out T: TCompXform);
var
  CA, SA, CB, SB, CG, SG: Double;
  GX, GY, GZ: Double;
begin
  T.Pos := Pos;
  T.Center := Vec3(C.Size.X * 0.5, C.Size.Y * 0.5, C.Size.Z * 0.5);
  T.GMin := M.BoundsMin;
  GX := M.BoundsMax.X - M.BoundsMin.X;
  GY := M.BoundsMax.Y - M.BoundsMin.Y;
  GZ := M.BoundsMax.Z - M.BoundsMin.Z;
  if GX > 1e-6 then T.Scale.X := C.Size.X / GX else T.Scale.X := 1;
  if GY > 1e-6 then T.Scale.Y := C.Size.Y / GY else T.Scale.Y := 1;
  if GZ > 1e-6 then T.Scale.Z := C.Size.Z / GZ else T.Scale.Z := 1;
  { R = Rz * Ry * Rx (graus) }
  CA := Cos(DegToRad(Rot.X)); SA := Sin(DegToRad(Rot.X));
  CB := Cos(DegToRad(Rot.Y)); SB := Sin(DegToRad(Rot.Y));
  CG := Cos(DegToRad(Rot.Z)); SG := Sin(DegToRad(Rot.Z));
  T.R[0, 0] := CG * CB; T.R[0, 1] := CG * SB * SA - SG * CA; T.R[0, 2] := CG * SB * CA + SG * SA;
  T.R[1, 0] := SG * CB; T.R[1, 1] := SG * SB * SA + CG * CA; T.R[1, 2] := SG * SB * CA - CG * SA;
  T.R[2, 0] := -SB;     T.R[2, 1] := CB * SA;                T.R[2, 2] := CB * CA;
end;

function TMechanicalAssemblyCanvas.XformPoint(const T: TCompXform; const V: TAssemblyVec3): TAssemblyVec3;
var
  LX, LY, LZ: Double;
begin
  LX := (V.X - T.GMin.X) * T.Scale.X - T.Center.X;
  LY := (V.Y - T.GMin.Y) * T.Scale.Y - T.Center.Y;
  LZ := (V.Z - T.GMin.Z) * T.Scale.Z - T.Center.Z;
  Result.X := T.Pos.X + T.Center.X + T.R[0, 0] * LX + T.R[0, 1] * LY + T.R[0, 2] * LZ;
  Result.Y := T.Pos.Y + T.Center.Y + T.R[1, 0] * LX + T.R[1, 1] * LY + T.R[1, 2] * LZ;
  Result.Z := T.Pos.Z + T.Center.Z + T.R[2, 0] * LX + T.R[2, 1] * LY + T.R[2, 2] * LZ;
end;

function TMechanicalAssemblyCanvas.XformNormal(const T: TCompXform; const N: TAssemblyVec3): TAssemblyVec3;
var
  LX, LY, LZ: Double;
begin
  { normal com escala nao uniforme: divide pela escala e normaliza }
  LX := N.X / Max(1e-6, T.Scale.X);
  LY := N.Y / Max(1e-6, T.Scale.Y);
  LZ := N.Z / Max(1e-6, T.Scale.Z);
  Result.X := T.R[0, 0] * LX + T.R[0, 1] * LY + T.R[0, 2] * LZ;
  Result.Y := T.R[1, 0] * LX + T.R[1, 1] * LY + T.R[1, 2] * LZ;
  Result.Z := T.R[2, 0] * LX + T.R[2, 1] * LY + T.R[2, 2] * LZ;
  Result := Vec3Normalize(Result);
end;

procedure TMechanicalAssemblyCanvas.ComponentCorners(const C: TAssemblyComponent; const Pos, Rot: TAssemblyVec3;
  out Corners: array of TAssemblyVec3);
var
  T: TCompXform;
  M: TAssemblyMesh;
  I: Integer;
begin
  M.BoundsMin := Vec3(0, 0, 0);
  M.BoundsMax := C.Size;
  MakeXform(C, Pos, Rot, M, T);
  for I := 0 to 7 do
    Corners[I] := XformPoint(T, Vec3(IfThen(I and 1 <> 0, C.Size.X, 0), IfThen(I and 2 <> 0, C.Size.Y, 0),
      IfThen(I and 4 <> 0, C.Size.Z, 0)));
end;

function TintColor(C, Target: TColor; F: Double): TColor;
var
  R, G, B: Integer;
begin
  C := ColorToRGB(C);
  R := Round(Red(C) * (1 - F) + Red(Target) * F);
  G := Round(Green(C) * (1 - F) + Green(Target) * F);
  B := Round(Blue(C) * (1 - F) + Blue(Target) * F);
  Result := RGBToColor(EnsureRange(R, 0, 255), EnsureRange(G, 0, 255), EnsureRange(B, 0, 255));
end;

procedure TMechanicalAssemblyCanvas.CollectComponentFaces(const C: TAssemblyComponent; const Pos, Rot: TAssemblyVec3;
  IsSelected, HasCollision, InCurrentStep: Boolean);
const
  LX = -0.43; LY = 0.66; LZ = -0.62;   // luz principal (camera): esquerda, acima, frente
var
  MI, I, J, NV, CX, CY: Integer;
  T: TCompXform;
  Depths: array of Double;
  FaceVis: array of Boolean;
  Wp, Nc, Nw: TAssemblyVec3;
  D, Diff, Spec, HX, HY, HZ, HL, Light, LLen, Lx_, Ly_, Lz_: Double;
  Base, Fill: TColor;
  RR, GG, BB: Integer;
begin
  MI := MeshIndexFor(C);
  MakeXform(C, Pos, Rot, FMeshCache[MI].Mesh, T);
  with FMeshCache[MI].Mesh do
  begin
    SetLength(Depths, Count);
    SetLength(FaceVis, Count);
    LLen := Sqrt(LX * LX + LY * LY + LZ * LZ);
    Lx_ := LX / LLen; Ly_ := LY / LLen; Lz_ := LZ / LLen;
    HX := Lx_; HY := Ly_; HZ := Lz_ - 1.0;
    HL := Sqrt(HX * HX + HY * HY + HZ * HZ);
    HX := HX / HL; HY := HY / HL; HZ := HZ / HL;

    { profundidade e visibilidade de todas as faces (decalques usam a da face hospedeira) }
    for I := 0 to Count - 1 do
    begin
      Nw := XformNormal(T, Faces[I].N);
      Nc := CameraDir(Nw);
      FaceVis[I] := Nc.Z < -1e-3;
      D := 0;
      NV := Length(Faces[I].V);
      for J := 0 to NV - 1 do
      begin
        Wp := XformPoint(T, Faces[I].V[J]);
        D := D + CameraDir(Vec3(Wp.X - FTargetCenter.X, Wp.Y - FTargetCenter.Y, Wp.Z - FTargetCenter.Z)).Z;
      end;
      if NV > 0 then D := D / NV;
      Depths[I] := D;
    end;

    for I := 0 to Count - 1 do
    begin
      if not FaceVis[I] then Continue;
      if Faces[I].Decal then
      begin
        if (Faces[I].Host >= 0) then
        begin
          if not FaceVis[Faces[I].Host] then Continue;
          D := Depths[Faces[I].Host] - 0.002;
        end
        else
          D := Depths[I] - 0.5;
      end
      else
        D := Depths[I];

      { sombreamento: ambiente + difusa + especular (Blinn-Phong) }
      Nc := CameraDir(XformNormal(T, Faces[I].N));
      Diff := Max(0.0, Nc.X * Lx_ + Nc.Y * Ly_ + Nc.Z * Lz_);
      Spec := Power(Max(0.0, Nc.X * HX + Nc.Y * HY + Nc.Z * HZ), 28) * 0.20;
      Light := 0.36 + 0.64 * Diff;
      if Faces[I].Decal then
      begin
        Light := 0.75 + 0.25 * Diff;
        Spec := 0;
      end;
      Base := TColor(Faces[I].Color);
      if HasCollision then
        Base := TintColor(Base, RGBToColor(230, 40, 40), 0.55)
      else if InCurrentStep then
        Base := TintColor(Base, RGBToColor(40, 140, 230), 0.40)
      else if IsSelected then
        Base := TintColor(Base, RGBToColor(255, 208, 0), 0.22);
      Base := ColorToRGB(Base);
      RR := Round(Red(Base) * Light + 255 * Spec);
      GG := Round(Green(Base) * Light + 255 * Spec);
      BB := Round(Blue(Base) * Light + 255 * Spec);
      Fill := RGBToColor(EnsureRange(RR, 0, 255), EnsureRange(GG, 0, 255), EnsureRange(BB, 0, 255));

      { projeta os vertices no buffer de pontos }
      NV := Length(Faces[I].V);
      if FPointCount + NV > Length(FPointBuf) then
        SetLength(FPointBuf, (FPointCount + NV) * 2 + 1024);
      for J := 0 to NV - 1 do
      begin
        Wp := XformPoint(T, Faces[I].V[J]);
        ProjectToScreen(Wp.X, Wp.Y, Wp.Z, CX, CY);
        FPointBuf[FPointCount + J] := Point(CX, CY);
      end;
      if FDrawCount >= Length(FDrawFaces) then
        SetLength(FDrawFaces, FDrawCount * 2 + 1024);
      FDrawFaces[FDrawCount].Start := FPointCount;
      FDrawFaces[FDrawCount].Count := NV;
      FDrawFaces[FDrawCount].Depth := D;
      FDrawFaces[FDrawCount].Fill := Fill;
      if Faces[I].Smooth or Faces[I].Decal then
        FDrawFaces[FDrawCount].Pen := Fill
      else
        FDrawFaces[FDrawCount].Pen := TColor(GeomShade(LongInt(Fill), 0.72));
      Inc(FDrawCount);
      Inc(FPointCount, NV);
    end;
  end;
end;

procedure TMechanicalAssemblyCanvas.SortDrawFaces;

  procedure QSort(L, R: Integer);
  var
    I, J: Integer;
    P: Double;
    Tmp: TDrawFace;
  begin
    repeat
      I := L;
      J := R;
      P := FDrawFaces[(L + R) shr 1].Depth;
      repeat
        while FDrawFaces[I].Depth > P do Inc(I);
        while FDrawFaces[J].Depth < P do Dec(J);
        if I <= J then
        begin
          Tmp := FDrawFaces[I];
          FDrawFaces[I] := FDrawFaces[J];
          FDrawFaces[J] := Tmp;
          Inc(I);
          Dec(J);
        end;
      until I > J;
      if L < J then QSort(L, J);
      L := I;
    until I >= R;
  end;

begin
  if FDrawCount > 1 then QSort(0, FDrawCount - 1);
end;

procedure TMechanicalAssemblyCanvas.DrawSelectionBox(const C: TAssemblyComponent; const Pos, Rot: TAssemblyVec3);
const
  Edges: array[0..11, 0..1] of Integer = ((0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7),
    (0, 4), (1, 5), (2, 6), (3, 7));
var
  K: array[0..7] of TAssemblyVec3;
  P: array[0..7] of TPoint;
  I: Integer;
begin
  ComponentCorners(C, Pos, Rot, K);
  for I := 0 to 7 do
    ProjectToScreen(K[I].X, K[I].Y, K[I].Z, P[I].X, P[I].Y);
  Canvas.Pen.Color := $00D0FF;
  Canvas.Pen.Width := 2;
  Canvas.Pen.Style := psDot;
  for I := 0 to 11 do
    Canvas.Line(P[Edges[I, 0]].X, P[Edges[I, 0]].Y, P[Edges[I, 1]].X, P[Edges[I, 1]].Y);
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := 1;
end;

procedure TMechanicalAssemblyCanvas.DrawComponentLabel(const C: TAssemblyComponent; const Pos, Rot: TAssemblyVec3;
  const LabelStr: string);
var
  K: array[0..7] of TAssemblyVec3;
  I, SX, SY, MinY, SumX, TW: Integer;
begin
  ComponentCorners(C, Pos, Rot, K);
  MinY := MaxInt;
  SumX := 0;
  for I := 0 to 7 do
  begin
    ProjectToScreen(K[I].X, K[I].Y, K[I].Z, SX, SY);
    MinY := Min(MinY, SY);
    Inc(SumX, SX);
  end;
  SX := SumX div 8;
  Canvas.Font.Size := 8;
  Canvas.Font.Style := [fsBold];
  TW := Canvas.TextWidth(LabelStr);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := $2D1E1E;
  Canvas.Pen.Color := $4A3A3A;
  Canvas.Rectangle(SX - TW div 2 - 4, MinY - 20, SX + TW div 2 + 4, MinY - 4);
  Canvas.Font.Color := $E2E8F0;
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(SX - TW div 2, MinY - 19, LabelStr);
  Canvas.Brush.Style := bsSolid;
end;

procedure TMechanicalAssemblyCanvas.Paint;
var
  I, StepI, GX, GY: Integer;
  C: TAssemblyComponent;
  Pos, Rot: TAssemblyVec3;
  DOF: TComponentDOF;
  IsSelected, IsInCurrentStep, HasCollision: Boolean;
  StepComps, CurrStepComps: TStringList;
  LabelStr, StatusStr: string;
  R: TMechanicalRelation;
  P1, P2: TPoint;
  SelIdx: Integer;
begin
  Canvas.Brush.Color := $1E1E28; // Fundo escuro premium MultiSuite
  Canvas.FillRect(ClientRect);
  UpdateCameraTrig;

  // Grade 3D
  Draw3DGrid;

  if FProject = nil then Exit;

  StepComps := nil;
  CurrStepComps := nil;
  if FActiveStep >= 0 then
  begin
    StepComps := GetStepComponents(FActiveStep);
    CurrStepComps := TStringList.Create;
    if FActiveStep < FProject.StepCount then
      for StepI := 0 to High(FProject.Step(FActiveStep).ComponentIDs) do
        CurrStepComps.Add(FProject.Step(FActiveStep).ComponentIDs[StepI]);
  end;

  try
    { 1. coleta as faces de todos os componentes visiveis }
    FPointCount := 0;
    FDrawCount := 0;
    SelIdx := -1;
    for I := 0 to FProject.ComponentCount - 1 do
    begin
      C := FProject.Component(I);
      if StepComps <> nil then
      begin
        if StepComps.IndexOf(C.ID) < 0 then Continue;
        IsInCurrentStep := (CurrStepComps <> nil) and (CurrStepComps.IndexOf(C.ID) >= 0);
      end
      else
        IsInCurrentStep := False;
      IsSelected := SameText(C.ID, FSelectedID);
      if IsSelected then SelIdx := I;
      if FSolver <> nil then Pos := FSolver.GetSolvedPosition(C.ID) else Pos := C.Position;
      Rot := ComponentRotation(C);
      HasCollision := IsPartColliding(C.ID);
      CollectComponentFaces(C, Pos, Rot, IsSelected, HasCollision, IsInCurrentStep);
    end;

    { 2. ordena da face mais distante para a mais proxima e desenha }
    SortDrawFaces;
    Canvas.Pen.Width := 1;
    Canvas.Brush.Style := bsSolid;
    for I := 0 to FDrawCount - 1 do
    begin
      Canvas.Brush.Color := FDrawFaces[I].Fill;
      Canvas.Pen.Color := FDrawFaces[I].Pen;
      Canvas.Polygon(FPointBuf, False, FDrawFaces[I].Start, FDrawFaces[I].Count);
    end;

    { 3. rotulos, selecao e setas de graus de liberdade }
    for I := 0 to FProject.ComponentCount - 1 do
    begin
      C := FProject.Component(I);
      if (StepComps <> nil) and (StepComps.IndexOf(C.ID) < 0) then Continue;
      if FSolver <> nil then
      begin
        Pos := FSolver.GetSolvedPosition(C.ID);
        DOF := FSolver.GetDOF(C.ID);
      end
      else
      begin
        Pos := C.Position;
        DOF.Status := adsUnderdefined;
        DOF.FreeCount := 6;
      end;
      Rot := ComponentRotation(C);
      if FShowLabels or (I = SelIdx) then
      begin
        LabelStr := C.ID;
        if DOF.Status = adsFixed then
          LabelStr := '(f) ' + LabelStr
        else if DOF.Status = adsUnderdefined then
          LabelStr := '(-) ' + LabelStr;
        DrawComponentLabel(C, Pos, Rot, LabelStr);
      end;
      if I = SelIdx then
      begin
        DrawSelectionBox(C, Pos, Rot);
        DrawDOFArrows(C.ID, Pos, C.Size, DOF);
      end;
    end;

    // Linhas cinemáticas / Junções mecânicas (Mates)
    if FShowMateLines then
    begin
      Canvas.Pen.Width := 2;
      for I := 0 to FProject.RelationCount - 1 do
      begin
        R := FProject.Relation(I);
        GX := FProject.FindComponent(R.A);
        GY := FProject.FindComponent(R.B);
        if (GX >= 0) and (GY >= 0) then
        begin
          if FSolver <> nil then
          begin
            ProjectToScreen(FSolver.GetSolvedPosition(R.A).X, FSolver.GetSolvedPosition(R.A).Y, FSolver.GetSolvedPosition(R.A).Z, P1.X, P1.Y);
            ProjectToScreen(FSolver.GetSolvedPosition(R.B).X, FSolver.GetSolvedPosition(R.B).Y, FSolver.GetSolvedPosition(R.B).Z, P2.X, P2.Y);
          end
          else
          begin
            ProjectToScreen(FProject.Component(GX).Position.X, FProject.Component(GX).Position.Y, FProject.Component(GX).Position.Z, P1.X, P1.Y);
            ProjectToScreen(FProject.Component(GY).Position.X, FProject.Component(GY).Position.Y, FProject.Component(GY).Position.Z, P2.X, P2.Y);
          end;

          case R.Kind of
            mrSlider, mrLeadScrew: Canvas.Pen.Color := $20D0A0; // Verde-agua para deslizador
            mrHinge: Canvas.Pen.Color := $E09020;               // Ambar para articulacao
            mrFixed: Canvas.Pen.Color := $506070;               // Cinza
          else
            Canvas.Pen.Color := $60A0C0;
          end;
          Canvas.Line(P1.X, P1.Y, P2.X, P2.Y);
        end;
      end;
      Canvas.Pen.Width := 1;
    end;

  finally
    StepComps.Free;
    CurrStepComps.Free;
  end;

  // Triedro 3D interativo nos cantos
  Draw3DTrihedron;

  // HUD Superior com informacoes de navegacao 3D e cinemática
  Canvas.Font.Size := 9;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := $94A3B8;
  Canvas.Brush.Style := bsClear;
  case FViewMode of
    avm3DOrbit: LabelStr := Format('VISTA 3D ORBITAL [Azimute: %.0f° | Elevação: %.0f°] • Botão Direito: Girar 3D • Botão Esquerdo: Mover Peça', [FAzimuth, FElevation]);
    avmTop: LabelStr := 'VISTA SUPERIOR (X-Y) • 2D / 3D';
    avmFront: LabelStr := 'VISTA FRONTAL (X-Z) • 2D / 3D';
    avmSide: LabelStr := 'VISTA LATERAL (Y-Z) • 2D / 3D';
  end;
  Canvas.TextOut(16, 16, LabelStr);

  if (FProject <> nil) and (FProject.ComponentCount = 0) then
  begin
    Canvas.Font.Size := 9;
    Canvas.Font.Style := [];
    Canvas.Font.Color := $64748B;
    Canvas.TextOut(16, 38, 'Montagem em branco: use "+ Inserir Peça na Montagem" na aba Componentes.');
  end;

  if (FSolver <> nil) and (FSolver.CollisionCount > 0) then
  begin
    Canvas.Font.Size := 9;
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := $5050FF;
    StatusStr := Format('⚠️ COLISÃO DETECTADA: %d ponto(s) de interferência entre peças!', [FSolver.CollisionCount]);
    Canvas.TextOut(16, 38, StatusStr);
  end;
  Canvas.Brush.Style := bsSolid;
end;

function TMechanicalAssemblyCanvas.HitTest(SX, SY: Integer): string;
var
  I, J, PX, PY: Integer;
  C: TAssemblyComponent;
  Pos: TAssemblyVec3;
  K: array[0..7] of TAssemblyVec3;
  MinX, MaxX, MinY, MaxY: Integer;
  D, Depth, BestDepth: Double;
begin
  Result := '';
  if FProject = nil then Exit;
  UpdateCameraTrig;
  BestDepth := MaxDouble;
  for I := FProject.ComponentCount - 1 downto 0 do
  begin
    C := FProject.Component(I);
    if FSolver <> nil then
      Pos := FSolver.GetSolvedPosition(C.ID)
    else
      Pos := C.Position;
    ComponentCorners(C, Pos, ComponentRotation(C), K);
    MinX := MaxInt; MaxX := -MaxInt; MinY := MaxInt; MaxY := -MaxInt;
    Depth := 0;
    for J := 0 to 7 do
    begin
      ProjectToScreen(K[J].X, K[J].Y, K[J].Z, PX, PY, D);
      MinX := Min(MinX, PX); MaxX := Max(MaxX, PX);
      MinY := Min(MinY, PY); MaxY := Max(MaxY, PY);
      Depth := Depth + D / 8;
    end;
    if (SX >= MinX - 4) and (SX <= MaxX + 4) and (SY >= MinY - 4) and (SY <= MaxY + 4) and (Depth < BestDepth) then
    begin
      BestDepth := Depth;
      Result := C.ID;
    end;
  end;
end;

procedure TMechanicalAssemblyCanvas.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  HitID: string;
  DOF: TComponentDOF;
begin
  SetFocus;
  FDragMouseX := X;
  FDragMouseY := Y;
  FDragStartX := X;
  FDragStartY := Y;
  FInitialPanX := FPanX;
  FInitialPanY := FPanY;
  FInitialAzimuth := FAzimuth;
  FInitialElevation := FElevation;

  if (Button = mbRight) or (ssShift in Shift) then
  begin
    // Botao direito = Orbita 3D livre (Camera Orbital)
    if ssShift in Shift then
      FPanning := True
    else
      FOrbiting := True;
    Cursor := crHandPoint;
    Exit;
  end;

  if Button = mbLeft then
  begin
    HitID := HitTest(X, Y);
    if HitID <> '' then
    begin
      FSelectedID := HitID;
      if Assigned(FOnSelect) then
        FOnSelect(Self, HitID);

      if FSolver <> nil then
        DOF := FSolver.GetDOF(HitID)
      else
      begin
        DOF.Status := adsUnderdefined;
        DOF.FreeCount := 6;
      end;

      if DOF.Status <> adsFixed then
      begin
        FDraggingPart := True;
        FDragPartID := HitID;
        Cursor := crSizeAll;
      end
      else
      begin
        // Peca fixa: orbita 3D em torno da cena
        FOrbiting := True;
        Cursor := crHandPoint;
      end;
      Invalidate;
    end
    else
    begin
      // Clicou no espaco vazio: orbita 3D
      FOrbiting := True;
      Cursor := crHandPoint;
    end;
  end;
end;

procedure TMechanicalAssemblyCanvas.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  DX, DY: Integer;
  RadAz, RadEl: Double;
  WorldDelta: TAssemblyVec3;
  DOF: TComponentDOF;
begin
  DX := X - FDragMouseX;
  DY := Y - FDragMouseY;

  if FOrbiting then
  begin
    // Rotacao 3D orbital continua da cena
    FAzimuth := FAzimuth + DX * 0.6;
    while FAzimuth >= 360.0 do FAzimuth := FAzimuth - 360.0;
    while FAzimuth < 0.0 do FAzimuth := FAzimuth + 360.0;

    FElevation := EnsureRange(FElevation - DY * 0.6, -89.0, 89.0);
    FDragMouseX := X;
    FDragMouseY := Y;
    Invalidate;
  end
  else if FPanning then
  begin
    FPanX := FInitialPanX + (X - FDragStartX);
    FPanY := FInitialPanY + (Y - FDragStartY);
    Invalidate;
  end
  else if FDraggingPart and (FDragPartID <> '') and (FSolver <> nil) then
  begin
    FDragMouseX := X;
    FDragMouseY := Y;

    DOF := FSolver.GetDOF(FDragPartID);
    RadAz := DegToRad(FAzimuth);
    RadEl := DegToRad(FElevation);

    WorldDelta := Vec3(0, 0, 0);

    // Mapeia deslocamento da tela 2D para o espaco 3D orientado pela camera
    if DOF.Tx and not DOF.Ty and not DOF.Tz then
      WorldDelta.X := (DX * Cos(RadAz) + DY * Sin(RadAz) * Sin(RadEl)) / FScale
    else if DOF.Ty and not DOF.Tx and not DOF.Tz then
      WorldDelta.Y := (-DX * Sin(RadAz) + DY * Cos(RadAz) * Sin(RadEl)) / FScale
    else if DOF.Tz and not DOF.Tx and not DOF.Ty then
      WorldDelta.Z := -DY / (FScale * Max(0.2, Cos(RadEl)))
    else
    begin
      WorldDelta.X := (DX * Cos(RadAz)) / FScale;
      WorldDelta.Y := (-DX * Sin(RadAz)) / FScale;
      WorldDelta.Z := -DY / FScale;
    end;

    FSolver.DragComponent(FDragPartID, WorldDelta);

    if Assigned(FOnKinematicMove) then
      FOnKinematicMove(Self, FDragPartID);

    Invalidate;
  end;
end;

procedure TMechanicalAssemblyCanvas.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FOrbiting := False;
  FPanning := False;
  FDraggingPart := False;
  FDragPartID := '';
  Cursor := crCross;
end;

function TMechanicalAssemblyCanvas.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  if WheelDelta > 0 then
    FScale := FScale * 1.15
  else
    FScale := Max(0.2, FScale / 1.15);
  Invalidate;
  Result := True;
end;

procedure TMechanicalAssemblyCanvas.FitToView;
var
  I: Integer;
  C: TAssemblyComponent;
  Pos: TAssemblyVec3;
  MinX, MaxX, MinY, MaxY, MinZ, MaxZ: Double;
  Span: Double;
begin
  if (FProject = nil) or (FProject.ComponentCount = 0) then
  begin
    FPanX := 0; FPanY := 0; FScale := 2.5;
    FTargetCenter := Vec3(80, 50, 20);
    Invalidate;
    Exit;
  end;

  MinX := 1e9; MaxX := -1e9;
  MinY := 1e9; MaxY := -1e9;
  MinZ := 1e9; MaxZ := -1e9;

  for I := 0 to FProject.ComponentCount - 1 do
  begin
    C := FProject.Component(I);
    if FSolver <> nil then
      Pos := FSolver.GetSolvedPosition(C.ID)
    else
      Pos := C.Position;

    MinX := Min(MinX, Pos.X);
    MaxX := Max(MaxX, Pos.X + C.Size.X);
    MinY := Min(MinY, Pos.Y);
    MaxY := Max(MaxY, Pos.Y + C.Size.Y);
    MinZ := Min(MinZ, Pos.Z);
    MaxZ := Max(MaxZ, Pos.Z + C.Size.Z);
  end;

  FTargetCenter := Vec3((MinX + MaxX) * 0.5, (MinY + MaxY) * 0.5, (MinZ + MaxZ) * 0.5);
  Span := Max(50.0, Max(MaxX - MinX, Max(MaxY - MinY, MaxZ - MinZ)));

  FScale := Min(Width / (Span * 2.2), Height / (Span * 2.2));
  FPanX := 0;
  FPanY := 0;
  Invalidate;
end;

procedure TMechanicalAssemblyCanvas.ZoomIn;
begin
  FScale := FScale * 1.25;
  Invalidate;
end;

procedure TMechanicalAssemblyCanvas.ZoomOut;
begin
  FScale := Max(0.2, FScale / 1.25);
  Invalidate;
end;

end.
