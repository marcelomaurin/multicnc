unit multiassembly_mechanical_canvas;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Math, LCLType, Forms,
  multiassembly_types, multiassembly_project, multiassembly_solver, multiassembly_geometry,
  multiassembly_mates;

type
  TAssemblyViewMode = (avm3DOrbit, avmTop, avmFront, avmSide);

  TComponentSelectEvent = procedure(Sender: TObject; const ComponentID: string) of object;
  TMateStatusEvent = procedure(Sender: TObject; const Msg: string) of object;

  { modo "Unir peças" (estilo SolidWorks Composer) }
  TMateMode = (mmNone, mmPickMoving, mmPickTarget, mmPreview);
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
    CompIdx, FaceIdx: Integer; // componente e face da malha (selecao)
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
    FCurCompIdx: Integer;

    // Uniao de pecas por referencia
    FMateMode: TMateMode;
    FHoverComp, FHoverFace: Integer;
    FHoverFeat: TMateFeature;
    FMoveID, FTargetID: string;
    FMoveFeat, FTargetFeat: TMateFeature;
    FMateKind: TMechanicalRelationKind;
    FMateFlip: Boolean;
    FMateSpin, FMateDist: Double;
    FPreviewOK: Boolean;
    FPreviewPos, FPreviewRot: TAssemblyVec3;
    FOnMateCreated: TNotifyEvent;
    FOnMateStatus: TMateStatusEvent;

    function PickFace(SX, SY: Integer; out CompIdx, FaceIdx: Integer): Boolean;
    function FeatureOf(CompIdx, FaceIdx: Integer): TMateFeature;
    procedure UpdateMatePreview;
    procedure MateStatus(const Msg: string);
    function MateHint: string;
    procedure DrawFeatureMarker(CompIdx: Integer; const F: TMateFeature; MarkColor: TColor; HighlightFaces: Boolean);
    procedure DrawMateOverlay;
    function PoseOf(const C: TAssemblyComponent; out Pos, Rot: TAssemblyVec3): Boolean;

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
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
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

    // Unir pecas: clique na face/furo/eixo da peca que se move e depois na
    // referencia; Enter confirma, F inverte, R gira 90°, C/O/I/D/P mudam o tipo.
    procedure StartMateMode;
    procedure CancelMateMode;
    function ConfirmMate: Boolean;
    procedure SetMateKind(Kind: TMechanicalRelationKind);
    procedure FlipMate;
    procedure SpinMate(DeltaDeg: Double);
    procedure SetMateDistance(Value: Double);
    property MateMode: TMateMode read FMateMode;
    property MateKind: TMechanicalRelationKind read FMateKind;
    property MateDistance: Double read FMateDist;

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
    property OnMateCreated: TNotifyEvent read FOnMateCreated write FOnMateCreated;
    property OnMateStatus: TMateStatusEvent read FOnMateStatus write FOnMateStatus;
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
  FMateMode := mmNone;
  FHoverComp := -1;
  FHoverFace := -1;
  FCurCompIdx := -1;
  TabStop := True;
  FOrbiting := False;
  FPanning := False;
  FDraggingPart := False;
  FDragPartID := '';
  if FMateMode <> mmNone then Cursor := crHandPoint else Cursor := crCross;
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
  GroupMin: array of Double;
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

    { profundidade minima de cada grupo coplanar: o decalque fica por cima
      de toda a face subdividida em que esta apoiado }
    SetLength(GroupMin, Count + 1);
    for I := 0 to Count do GroupMin[I] := MaxDouble;
    for I := 0 to Count - 1 do
      if (Faces[I].Group >= 0) and (Faces[I].Group <= Count) and FaceVis[I] then
        GroupMin[Faces[I].Group] := Min(GroupMin[Faces[I].Group], Depths[I]);

    for I := 0 to Count - 1 do
    begin
      if not FaceVis[I] then Continue;
      if Faces[I].Decal then
      begin
        if (Faces[I].Host >= 0) then
        begin
          if not FaceVis[Faces[I].Host] then Continue;
          D := Depths[Faces[I].Host];
          if (Faces[Faces[I].Host].Group >= 0) and (GroupMin[Faces[Faces[I].Host].Group] < MaxDouble) then
            D := Min(D, GroupMin[Faces[Faces[I].Host].Group]);
          D := D - 0.002;
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
        Base := TintColor(Base, RGBToColor(255, 208, 0), 0.15);
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
      FDrawFaces[FDrawCount].CompIdx := FCurCompIdx;
      FDrawFaces[FDrawCount].FaceIdx := I;
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
      PoseOf(C, Pos, Rot);
      HasCollision := IsPartColliding(C.ID) and (FMateMode = mmNone);
      if FMateMode <> mmNone then
      begin
        IsSelected := SameText(C.ID, FTargetID);           // referencia: realce dourado
        IsInCurrentStep := SameText(C.ID, FMoveID);        // peca que se move: realce azul
      end;
      FCurCompIdx := I;
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

    if FMateMode <> mmNone then
      DrawMateOverlay;

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
      PoseOf(C, Pos, Rot);
      if (FShowLabels and (FMateMode = mmNone)) or (I = SelIdx) then
      begin
        LabelStr := C.ID;
        if DOF.Status = adsFixed then
          LabelStr := '(f) ' + LabelStr
        else if DOF.Status = adsUnderdefined then
          LabelStr := '(-) ' + LabelStr;
        DrawComponentLabel(C, Pos, Rot, LabelStr);
      end;
      if (I = SelIdx) and (FMateMode = mmNone) then
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

  if FMateMode <> mmNone then
  begin
    Canvas.Font.Size := 10;
    Canvas.Font.Style := [fsBold];
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := $3A2A12;
    Canvas.Pen.Color := $C08030;
    StatusStr := MateHint;
    Canvas.Rectangle(12, Height - 112, Min(Width - 12, 28 + Canvas.TextWidth(StatusStr)), Height - 82);
    Canvas.Font.Color := $FFE0B0;
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(20, Height - 106, StatusStr);
  end;

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

{ ------------------------------------------------------ unir pecas (mates) }

function TMechanicalAssemblyCanvas.PoseOf(const C: TAssemblyComponent; out Pos, Rot: TAssemblyVec3): Boolean;
begin
  Result := (FMateMode = mmPreview) and FPreviewOK and SameText(C.ID, FMoveID);
  if Result then
  begin
    Pos := FPreviewPos;
    Rot := FPreviewRot;
    Exit;
  end;
  if FSolver <> nil then Pos := FSolver.GetSolvedPosition(C.ID) else Pos := C.Position;
  Rot := ComponentRotation(C);
end;

function PointInScreenPoly(const Pts: array of TPoint; Start, Count, X, Y: Integer): Boolean;
var
  I, J: Integer;
  A, B: TPoint;
begin
  Result := False;
  J := Start + Count - 1;
  for I := Start to Start + Count - 1 do
  begin
    A := Pts[I];
    B := Pts[J];
    if ((A.Y > Y) <> (B.Y > Y)) and (X < (B.X - A.X) * (Y - A.Y) / (B.Y - A.Y) + A.X) then
      Result := not Result;
    J := I;
  end;
end;

function TMechanicalAssemblyCanvas.PickFace(SX, SY: Integer; out CompIdx, FaceIdx: Integer): Boolean;
var
  I: Integer;
begin
  CompIdx := -1;
  FaceIdx := -1;
  { a ultima face desenhada e a que esta por cima }
  for I := FDrawCount - 1 downto 0 do
    if PointInScreenPoly(FPointBuf, FDrawFaces[I].Start, FDrawFaces[I].Count, SX, SY) then
    begin
      CompIdx := FDrawFaces[I].CompIdx;
      FaceIdx := FDrawFaces[I].FaceIdx;
      Exit(CompIdx >= 0);
    end;
  Result := False;
end;

function TMechanicalAssemblyCanvas.FeatureOf(CompIdx, FaceIdx: Integer): TMateFeature;
var
  C: TAssemblyComponent;
  MI: Integer;
  G: TAssemblyGeometry;
begin
  Result := Default(TMateFeature);
  if (FProject = nil) or (CompIdx < 0) or (CompIdx >= FProject.ComponentCount) then Exit;
  C := FProject.Component(CompIdx);
  MI := MeshIndexFor(C);
  G := ComponentGeometry(C);
  Result := MeshToLocalFeature(FaceFeature(G, FMeshCache[MI].Mesh, FaceIdx), FMeshCache[MI].Mesh, C.Size);
end;

procedure TMechanicalAssemblyCanvas.MateStatus(const Msg: string);
begin
  if Assigned(FOnMateStatus) then FOnMateStatus(Self, Msg);
end;

function FeatureKindText(const F: TMateFeature): string;
begin
  if F.HasPlane and F.HasAxis then
    Result := Format('face circular Ø%.1f', [F.Radius * 2])
  else if F.HasAxis then
    Result := Format('eixo/furo Ø%.1f', [F.Radius * 2])
  else if F.HasPlane then
    Result := 'face plana'
  else
    Result := 'referência';
end;

function TMechanicalAssemblyCanvas.MateHint: string;
begin
  case FMateMode of
    mmPickMoving:
      Result := 'UNIR PEÇAS 1/2 • Clique na face, furo ou eixo da peça que vai se MOVER  •  [Esc] cancelar';
    mmPickTarget:
      Result := Format('UNIR PEÇAS 2/2 • %s (%s) • Agora clique na REFERÊNCIA na outra peça  •  [Esc] cancelar',
        [FMoveID, FeatureKindText(FMoveFeat)]);
    mmPreview:
      begin
        Result := Format('%s: %s → %s', [MateKindName(FMateKind), FMoveID, FTargetID]);
        if FMateKind = mrDistance then Result := Result + Format(' (%.1f mm)', [FMateDist]);
        if FMateFlip then Result := Result + ' • invertido';
        if Abs(FMateSpin) > 0.01 then Result := Result + Format(' • giro %.0f°', [FMateSpin]);
        Result := Result + '   [Enter] confirmar  [F] inverter  [R] girar 90°  [I] inserir  [O] concêntrico  ' +
          '[C] coincidente  [D] distância [+/-]  [P] paralelo  [Esc] cancelar';
      end;
  else
    Result := '';
  end;
end;

procedure TMechanicalAssemblyCanvas.StartMateMode;
begin
  FMateMode := mmPickMoving;
  FMoveID := '';
  FTargetID := '';
  FMoveFeat := Default(TMateFeature);
  FTargetFeat := Default(TMateFeature);
  FHoverComp := -1;
  FHoverFace := -1;
  FMateFlip := False;
  FMateSpin := 0;
  FMateDist := 0;
  FPreviewOK := False;
  Cursor := crHandPoint;
  if CanFocus then SetFocus;
  MateStatus('Unir peças: clique na face, furo ou eixo da peça que vai se mover.');
  Invalidate;
end;

procedure TMechanicalAssemblyCanvas.CancelMateMode;
begin
  if FMateMode = mmNone then Exit;
  FMateMode := mmNone;
  FPreviewOK := False;
  FHoverComp := -1;
  Cursor := crCross;
  MateStatus('União cancelada.');
  Invalidate;
end;

procedure TMechanicalAssemblyCanvas.UpdateMatePreview;
var
  IA, IB: Integer;
  CA, CB: TAssemblyComponent;
  PB, RB, PA, RA: TAssemblyVec3;
  WB: TMateFeature;
begin
  FPreviewOK := False;
  if FProject = nil then Exit;
  IA := FProject.FindComponent(FMoveID);
  IB := FProject.FindComponent(FTargetID);
  if (IA < 0) or (IB < 0) then Exit;
  CA := FProject.Component(IA);
  CB := FProject.Component(IB);
  if FSolver <> nil then
  begin
    PA := FSolver.GetSolvedPosition(CA.ID); RA := FSolver.GetSolvedRotation(CA.ID);
    PB := FSolver.GetSolvedPosition(CB.ID); RB := FSolver.GetSolvedRotation(CB.ID);
  end
  else
  begin
    PA := CA.Position; RA := CA.Rotation;
    PB := CB.Position; RB := CB.Rotation;
  end;
  WB := FeatureToWorld(CB, PB, RB, FTargetFeat);
  FPreviewOK := SolveMatePose(CA, PA, RA, FMoveFeat, WB, FMateKind, FMateFlip, FMateSpin, FMateDist,
    FPreviewPos, FPreviewRot);
  if FPreviewOK then
    MateStatus(Format('Prévia: %s. Enter confirma, F inverte, R gira.', [MateKindName(FMateKind)]))
  else
    MateStatus(Format('%s não se aplica a estas referências.', [MateKindName(FMateKind)]));
  Invalidate;
end;

procedure TMechanicalAssemblyCanvas.SetMateKind(Kind: TMechanicalRelationKind);
begin
  if FMateMode <> mmPreview then Exit;
  if not MateKindAllowed(FMoveFeat, FTargetFeat, Kind) then
  begin
    MateStatus(Format('%s exige outras referências (%s com %s).',
      [MateKindName(Kind), FeatureKindText(FMoveFeat), FeatureKindText(FTargetFeat)]));
    Exit;
  end;
  FMateKind := Kind;
  UpdateMatePreview;
end;

procedure TMechanicalAssemblyCanvas.FlipMate;
begin
  if FMateMode <> mmPreview then Exit;
  FMateFlip := not FMateFlip;
  UpdateMatePreview;
end;

procedure TMechanicalAssemblyCanvas.SpinMate(DeltaDeg: Double);
begin
  if FMateMode <> mmPreview then Exit;
  FMateSpin := FMateSpin + DeltaDeg;
  while FMateSpin >= 360 do FMateSpin := FMateSpin - 360;
  while FMateSpin < 0 do FMateSpin := FMateSpin + 360;
  UpdateMatePreview;
end;

procedure TMechanicalAssemblyCanvas.SetMateDistance(Value: Double);
begin
  FMateDist := Value;
  if FMateMode = mmPreview then
  begin
    if (FMateKind = mrCoincident) and (Abs(Value) > 1e-9) then FMateKind := mrDistance;
    UpdateMatePreview;
  end;
end;

function TMechanicalAssemblyCanvas.ConfirmMate: Boolean;
var
  R: TMechanicalRelation;
  IA, IB: Integer;
  C, CB: TAssemblyComponent;
  WB: TMateFeature;
begin
  Result := False;
  if (FMateMode <> mmPreview) or not FPreviewOK or (FProject = nil) then Exit;
  IA := FProject.FindComponent(FMoveID);
  IB := FProject.FindComponent(FTargetID);
  if (IA < 0) or (IB < 0) then Exit;

  C := FProject.Component(IA);
  C.Position := FPreviewPos;
  C.Rotation := FPreviewRot;
  FProject.UpdateComponent(IA, C);

  CB := FProject.Component(IB);
  WB := FeatureToWorld(CB, CB.Position, CB.Rotation, FTargetFeat);
  R := Default(TMechanicalRelation);
  R.A := FMoveID;
  R.B := FTargetID;
  R.Kind := FMateKind;
  R.Ratio := 1;
  R.Flipped := FMateFlip;
  R.SpinDeg := FMateSpin;
  R.Distance := FMateDist;
  R.HasRefs := True;
  R.RefA := FMoveFeat;
  R.RefB := FTargetFeat;
  if WB.HasAxis and (FMateKind in [mrConcentric, mrInsert]) then
    R.Axis := DominantAxis(WB.AxisDir)
  else if WB.HasPlane then
    R.Axis := DominantAxis(WB.PlaneNormal)
  else
    R.Axis := DominantAxis(WB.AxisDir);
  FProject.Relate(R);

  FMateMode := mmNone;
  FPreviewOK := False;
  Cursor := crCross;
  if FSolver <> nil then FSolver.Solve;
  FSelectedID := FMoveID;
  MateStatus(Format('União criada: %s %s → %s.', [MateKindName(R.Kind), R.A, R.B]));
  if Assigned(FOnMateCreated) then FOnMateCreated(Self);
  Invalidate;
  Result := True;
end;

procedure TMechanicalAssemblyCanvas.DrawFeatureMarker(CompIdx: Integer; const F: TMateFeature; MarkColor: TColor;
  HighlightFaces: Boolean);
var
  C: TAssemblyComponent;
  Pos, Rot, U, V, P0, Q: TAssemblyVec3;
  W: TMateFeature;
  I, J, K, MI: Integer;
  L: Double;
  Pts: array[0..32] of TPoint;
  A, B: TPoint;
begin
  if (FProject = nil) or (CompIdx < 0) or (CompIdx >= FProject.ComponentCount) or not F.Valid then Exit;
  C := FProject.Component(CompIdx);
  PoseOf(C, Pos, Rot);
  W := FeatureToWorld(C, Pos, Rot, F);
  Canvas.Brush.Style := bsClear;

  { contorno das faces da mesma parte (face plana inteira, lateral do cilindro) }
  if HighlightFaces then
  begin
    MI := MeshIndexFor(C);
    Canvas.Pen.Color := MarkColor;
    Canvas.Pen.Width := 2;
    for I := 0 to FDrawCount - 1 do
    begin
      if FDrawFaces[I].CompIdx <> CompIdx then Continue;
      K := FDrawFaces[I].FaceIdx;
      if (FMeshCache[MI].Mesh.Faces[K].Prim <> F.Prim) or (FMeshCache[MI].Mesh.Faces[K].Part <> F.Part) then Continue;
      if F.HasPlane and not F.HasAxis and (FHoverFace >= 0) and (CompIdx = FHoverComp) and
         (Vec3Dot(FMeshCache[MI].Mesh.Faces[K].N, FMeshCache[MI].Mesh.Faces[FHoverFace].N) < 0.99) then Continue;
      for J := 0 to FDrawFaces[I].Count - 1 do
      begin
        A := FPointBuf[FDrawFaces[I].Start + J];
        B := FPointBuf[FDrawFaces[I].Start + (J + 1) mod FDrawFaces[I].Count];
        Canvas.Line(A.X, A.Y, B.X, B.Y);
      end;
    end;
  end;

  Canvas.Pen.Width := 2;
  Canvas.Pen.Color := MarkColor;
  if F.HasAxis then
  begin
    { eixo tracejado e circulo do furo/eixo }
    L := Max(25.0, Max(C.Size.X, Max(C.Size.Y, C.Size.Z)) * 0.7);
    Canvas.Pen.Style := psDash;
    Canvas.Pen.Width := 1;
    ProjectToScreen(W.AxisPoint.X - W.AxisDir.X * L, W.AxisPoint.Y - W.AxisDir.Y * L, W.AxisPoint.Z - W.AxisDir.Z * L, A.X, A.Y);
    ProjectToScreen(W.AxisPoint.X + W.AxisDir.X * L, W.AxisPoint.Y + W.AxisDir.Y * L, W.AxisPoint.Z + W.AxisDir.Z * L, B.X, B.Y);
    Canvas.Line(A.X, A.Y, B.X, B.Y);
    Canvas.Pen.Style := psSolid;
    Canvas.Pen.Width := 2;
    U := Vec3Cross(W.AxisDir, Vec3(0, 0, 1));
    if Vec3Len(U) < 0.1 then U := Vec3Cross(W.AxisDir, Vec3(1, 0, 0));
    U := Vec3Normalize(U);
    V := Vec3Normalize(Vec3Cross(W.AxisDir, U));
    if F.HasPlane then P0 := W.PlanePoint else P0 := W.AxisPoint;
    for I := 0 to 32 do
    begin
      Q := Vec3Add(P0, Vec3Add(Vec3Mul(U, Cos(I * Pi / 16) * Max(0.5, F.Radius)), Vec3Mul(V, Sin(I * Pi / 16) * Max(0.5, F.Radius))));
      ProjectToScreen(Q.X, Q.Y, Q.Z, Pts[I].X, Pts[I].Y);
    end;
    Canvas.Polyline(Pts);
  end;
  if F.HasPlane then
  begin
    { seta da normal da face }
    L := Max(12.0, Max(C.Size.X, Max(C.Size.Y, C.Size.Z)) * 0.25);
    ProjectToScreen(W.PlanePoint.X, W.PlanePoint.Y, W.PlanePoint.Z, A.X, A.Y);
    ProjectToScreen(W.PlanePoint.X + W.PlaneNormal.X * L, W.PlanePoint.Y + W.PlaneNormal.Y * L,
      W.PlanePoint.Z + W.PlaneNormal.Z * L, B.X, B.Y);
    Canvas.Line(A.X, A.Y, B.X, B.Y);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := MarkColor;
    Canvas.Ellipse(B.X - 3, B.Y - 3, B.X + 4, B.Y + 4);
    Canvas.Ellipse(A.X - 3, A.Y - 3, A.X + 4, A.Y + 4);
  end;
  Canvas.Brush.Style := bsSolid;
  Canvas.Pen.Width := 1;
end;

procedure TMechanicalAssemblyCanvas.DrawMateOverlay;
var
  IA, IB: Integer;
begin
  if FProject = nil then Exit;
  IA := FProject.FindComponent(FMoveID);
  IB := FProject.FindComponent(FTargetID);
  if (FMateMode in [mmPickTarget, mmPreview]) and (IA >= 0) then
    DrawFeatureMarker(IA, FMoveFeat, $20A0FF, False);       // laranja: peca que se move
  if (FMateMode = mmPreview) and (IB >= 0) then
    DrawFeatureMarker(IB, FTargetFeat, $40E040, False);     // verde: referencia
  if (FMateMode in [mmPickMoving, mmPickTarget]) and (FHoverComp >= 0) and FHoverFeat.Valid then
    DrawFeatureMarker(FHoverComp, FHoverFeat, $FFE000, True); // ciano: sob o mouse
end;

procedure TMechanicalAssemblyCanvas.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if FMateMode <> mmNone then
  begin
    case Key of
      VK_ESCAPE: CancelMateMode;
      VK_RETURN: ConfirmMate;
      VK_F: FlipMate;
      VK_R: if ssShift in Shift then SpinMate(-90) else SpinMate(90);
      VK_I: SetMateKind(mrInsert);
      VK_O: SetMateKind(mrConcentric);
      VK_C: SetMateKind(mrCoincident);
      VK_P: SetMateKind(mrParallel);
      VK_D:
        begin
          SetMateKind(mrDistance);
        end;
      VK_ADD, VK_OEM_PLUS: SetMateDistance(FMateDist + IfThen(ssShift in Shift, 10, 1));
      VK_SUBTRACT, VK_OEM_MINUS: SetMateDistance(FMateDist - IfThen(ssShift in Shift, 10, 1));
    else
      begin
        inherited KeyDown(Key, Shift);
        Exit;
      end;
    end;
    Key := 0;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

procedure TMechanicalAssemblyCanvas.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  HitID: string;
  DOF: TComponentDOF;
  CI, FI: Integer;
  F: TMateFeature;
  C: TAssemblyComponent;
  K: TMechanicalRelationKind;
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

  if (Button = mbLeft) and (FMateMode <> mmNone) then
  begin
    if (FMateMode in [mmPickMoving, mmPickTarget]) and PickFace(X, Y, CI, FI) then
    begin
      F := FeatureOf(CI, FI);
      C := FProject.Component(CI);
      if not F.Valid then
        MateStatus('Não foi possível usar esta face como referência.')
      else if FMateMode = mmPickMoving then
      begin
        if C.Fixed then
          MateStatus(C.ID + ' é a base fixa e não se move: escolha primeiro a peça livre.')
        else
        begin
          FMoveID := C.ID;
          FMoveFeat := F;
          FMateMode := mmPickTarget;
          MateStatus(Format('%s: %s. Agora clique na referência da outra peça.', [C.ID, FeatureKindText(F)]));
        end;
      end
      else if SameText(C.ID, FMoveID) then
        MateStatus('A referência precisa estar em outra peça.')
      else
      begin
        FTargetID := C.ID;
        FTargetFeat := F;
        if SuggestMateKind(FMoveFeat, FTargetFeat, K) then
        begin
          FMateKind := K;
          FMateFlip := False;
          FMateSpin := 0;
          FMateMode := mmPreview;
          UpdateMatePreview;
        end
        else
          MateStatus(Format('Não há união entre %s e %s.', [FeatureKindText(FMoveFeat), FeatureKindText(F)]));
      end;
      Invalidate;
    end
    else
    begin
      FOrbiting := True;
      Cursor := crHandPoint;
    end;
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
  CI, FI: Integer;
  DX, DY: Integer;
  RadAz, RadEl: Double;
  WorldDelta: TAssemblyVec3;
  DOF: TComponentDOF;
begin
  DX := X - FDragMouseX;
  DY := Y - FDragMouseY;

  if (FMateMode in [mmPickMoving, mmPickTarget]) and not FOrbiting and not FPanning then
  begin
    if PickFace(X, Y, CI, FI) then
    begin
      if (CI <> FHoverComp) or (FI <> FHoverFace) then
      begin
        FHoverComp := CI;
        FHoverFace := FI;
        FHoverFeat := FeatureOf(CI, FI);
        Invalidate;
      end;
    end
    else if FHoverComp >= 0 then
    begin
      FHoverComp := -1;
      FHoverFace := -1;
      FHoverFeat := Default(TMateFeature);
      Invalidate;
    end;
  end;

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
  if FMateMode <> mmNone then Cursor := crHandPoint else Cursor := crCross;
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
