unit multiassembly_mechanical_canvas;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Math, LCLType, Forms,
  multiassembly_types, multiassembly_project, multiassembly_solver;

type
  TAssemblyViewMode = (avm3DOrbit, avmTop, avmFront, avmSide);

  TComponentSelectEvent = procedure(Sender: TObject; const ComponentID: string) of object;
  TKinematicMoveEvent = procedure(Sender: TObject; const ComponentID: string) of object;

  TFace3D = record
    P: array[0..3] of TPoint;
    AvgDepth: Double;
    Color: TColor;
    BorderColor: TColor;
  end;

  TCompRenderItem = record
    CompIndex: Integer;
    AvgDepth: Double;
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
    FOnSelect: TComponentSelectEvent;
    FOnKinematicMove: TKinematicMoveEvent;

    procedure ProjectToScreen(X, Y, Z: Double; out SX, SY: Integer; out Depth: Double); overload;
    procedure ProjectToScreen(X, Y, Z: Double; out SX, SY: Integer); overload;
    function HitTest(SX, SY: Integer): string;
    function GetStepComponents(StepIdx: Integer): TStringList;
    function IsPartColliding(const CompID: string): Boolean;
    procedure Draw3DTrihedron;
    procedure Draw3DGrid;
    procedure DrawDOFArrows(const CompID: string; const Pos, Size: TAssemblyVec3; const DOF: TComponentDOF);
    procedure DrawArrow(X0, Y0, Z0, DX, DY, DZ: Double; AColor: TColor; const ALabel: string);
    procedure RenderBox3D(const Pos, Size: TAssemblyVec3; BaseColor: TColor; IsSelected, HasCollision, InCurrentStep: Boolean; const LabelStr: string);
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
    property OnSelectComponent: TComponentSelectEvent read FOnSelect write FOnSelect;
    property OnKinematicMove: TKinematicMoveEvent read FOnKinematicMove write FOnKinematicMove;
  end;

implementation

function ColorForKind(K: TAssemblyComponentKind): TColor;
begin
  case K of
    ackMechanicalPart: Result := $C0B0A0; // Aco/Aluminio
    ackMotor: Result := $805030;          // Cobre/Azul motor
    ackSpindle: Result := $2090D0;        // Dourado metalico
    ackLeadScrew: Result := $A8A8A8;      // Inox
    ackLinearGuide: Result := $908070;    // Trilho de aco
    ackBearing: Result := $B08050;        // Bronze/Rolamento
    ackPulley: Result := $404040;         // Alum escuro
    ackBelt: Result := $202020;           // Preto borracha
    ackController, ackPCB: Result := $308040; // Verde PCB
    ackDriver: Result := $802060;         // Roxo escuro
    ackPowerSupply: Result := $888888;    // Prata industrial
    ackEStop: Result := $2020D0;          // Vermelho
    ackFastenerScrew, ackFastenerNut, ackFastenerWasher: Result := $D0D0D0; // Inox
    ackPinSpacer, ackFastenerRivet: Result := $90B0C0;
    ackSensor, ackEndStop: Result := $2080F0; // Laranja
  else
    Result := $A0A0A0;
  end;
end;

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

procedure TMechanicalAssemblyCanvas.RenderBox3D(const Pos, Size: TAssemblyVec3; BaseColor: TColor;
  IsSelected, HasCollision, InCurrentStep: Boolean; const LabelStr: string);
var
  X0, Y0, Z0, W, H, D: Double;
  P: array[0..7] of TPoint;
  Depths: array[0..7] of Double;
  Faces: array[0..5] of TFace3D;
  FCount, FI, FJ: Integer;
  TempFace: TFace3D;
  CX, CY: Integer;
  BorderCol: TColor;

  procedure AddFace(P0, P1, P2, P3: Integer; Factor: Double);
  var
    AvgD: Double;
    R, G, B: Integer;
  begin
    AvgD := (Depths[P0] + Depths[P1] + Depths[P2] + Depths[P3]) * 0.25;
    R := EnsureRange(Round(Red(ColorToRGB(BaseColor)) * Factor), 0, 255);
    G := EnsureRange(Round(Green(ColorToRGB(BaseColor)) * Factor), 0, 255);
    B := EnsureRange(Round(Blue(ColorToRGB(BaseColor)) * Factor), 0, 255);

    Faces[FCount].P[0] := P[P0];
    Faces[FCount].P[1] := P[P1];
    Faces[FCount].P[2] := P[P2];
    Faces[FCount].P[3] := P[P3];
    Faces[FCount].AvgDepth := AvgD;
    Faces[FCount].Color := RGBToColor(R, G, B);
    Faces[FCount].BorderColor := BorderCol;
    Inc(FCount);
  end;

begin
  X0 := Pos.X; Y0 := Pos.Y; Z0 := Pos.Z;
  W := Max(4.0, Size.X);
  H := Max(4.0, Size.Y);
  D := Max(4.0, Size.Z);

  // Calcula os 8 vertices projetados em 3D com profundidade
  ProjectToScreen(X0,     Y0,     Z0,     P[0].X, P[0].Y, Depths[0]);
  ProjectToScreen(X0 + W, Y0,     Z0,     P[1].X, P[1].Y, Depths[1]);
  ProjectToScreen(X0 + W, Y0 + H, Z0,     P[2].X, P[2].Y, Depths[2]);
  ProjectToScreen(X0,     Y0 + H, Z0,     P[3].X, P[3].Y, Depths[3]);

  ProjectToScreen(X0,     Y0,     Z0 + D, P[4].X, P[4].Y, Depths[4]);
  ProjectToScreen(X0 + W, Y0,     Z0 + D, P[5].X, P[5].Y, Depths[5]);
  ProjectToScreen(X0 + W, Y0 + H, Z0 + D, P[6].X, P[6].Y, Depths[6]);
  ProjectToScreen(X0,     Y0 + H, Z0 + D, P[7].X, P[7].Y, Depths[7]);

  if HasCollision then
    BaseColor := $2020E0
  else if InCurrentStep then
    BaseColor := $D08020;

  BorderCol := RGBToColor(Max(0, Red(ColorToRGB(BaseColor)) - 60),
                          Max(0, Green(ColorToRGB(BaseColor)) - 60),
                          Max(0, Blue(ColorToRGB(BaseColor)) - 60));

  FCount := 0;
  // Face Superior (+Z)
  AddFace(4, 5, 6, 7, 1.00);
  // Face Inferior (-Z)
  AddFace(0, 3, 2, 1, 0.45);
  // Face Frontal (-Y)
  AddFace(0, 1, 5, 4, 0.85);
  // Face Traseira (+Y)
  AddFace(3, 7, 6, 2, 0.60);
  // Face Direita (+X)
  AddFace(1, 2, 6, 5, 0.70);
  // Face Esquerda (-X)
  AddFace(0, 4, 7, 3, 0.75);

  // Ordena as 6 faces da mais distante para a mais proxima (Painter's Algorithm)
  for FI := 0 to FCount - 2 do
    for FJ := FI + 1 to FCount - 1 do
      if Faces[FI].AvgDepth < Faces[FJ].AvgDepth then
      begin
        TempFace := Faces[FI];
        Faces[FI] := Faces[FJ];
        Faces[FJ] := TempFace;
      end;

  // Renderiza faces sombreadas
  for FI := 0 to FCount - 1 do
  begin
    Canvas.Brush.Color := Faces[FI].Color;
    Canvas.Pen.Color := Faces[FI].BorderColor;
    Canvas.Pen.Width := 1;
    Canvas.Polygon(Faces[FI].P);
  end;

  // Destaque de selecao
  if IsSelected then
  begin
    Canvas.Pen.Color := $00D0FF;
    Canvas.Pen.Width := 3;
    Canvas.Brush.Style := bsClear;
    Canvas.Polygon([P[4], P[5], P[6], P[7]]);
    Canvas.Line(P[0].X, P[0].Y, P[4].X, P[4].Y);
    Canvas.Line(P[1].X, P[1].Y, P[5].X, P[5].Y);
    Canvas.Line(P[2].X, P[2].Y, P[6].X, P[6].Y);
    Canvas.Line(P[3].X, P[3].Y, P[7].X, P[7].Y);
    Canvas.Brush.Style := bsSolid;
  end;

  // Rotulo
  CX := (P[4].X + P[6].X) div 2;
  CY := (P[4].Y + P[6].Y) div 2 - 12;
  Canvas.Font.Size := 8;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := $E2E8F0;
  Canvas.Brush.Color := $2D1E1E;
  Canvas.TextOut(CX - Canvas.TextWidth(LabelStr) div 2, CY, LabelStr);
end;

procedure TMechanicalAssemblyCanvas.Paint;
var
  I, J, StepI, GX, GY: Integer;
  C: TAssemblyComponent;
  Pos: TAssemblyVec3;
  DOF: TComponentDOF;
  IsSelected, IsInCurrentStep, HasCollision: Boolean;
  StepComps, CurrStepComps: TStringList;
  LabelStr, StatusStr: string;
  R: TMechanicalRelation;
  OrderList: array of TCompRenderItem;
  TempItem: TCompRenderItem;
  D0, D1, D2: Double;
  P1, P2: TPoint;
begin
  Canvas.Brush.Color := $1E1E28; // Fundo escuro premium MultiSuite
  Canvas.FillRect(ClientRect);

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
    // Ordena componentes da cena por profundidade 3D (Z de camera)
    SetLength(OrderList, FProject.ComponentCount);
    for I := 0 to FProject.ComponentCount - 1 do
    begin
      C := FProject.Component(I);
      if FSolver <> nil then
        Pos := FSolver.GetSolvedPosition(C.ID)
      else
        Pos := C.Position;

      ProjectToScreen(Pos.X + C.Size.X * 0.5, Pos.Y + C.Size.Y * 0.5, Pos.Z + C.Size.Z * 0.5, P1.X, P1.Y, D0);
      OrderList[I].CompIndex := I;
      OrderList[I].AvgDepth := D0;
    end;

    for I := 0 to High(OrderList) - 1 do
      for J := I + 1 to High(OrderList) do
        if OrderList[I].AvgDepth < OrderList[J].AvgDepth then
        begin
          TempItem := OrderList[I];
          OrderList[I] := OrderList[J];
          OrderList[J] := TempItem;
        end;

    // Desenha componentes tridimensionais ordenados
    for I := 0 to High(OrderList) do
    begin
      C := FProject.Component(OrderList[I].CompIndex);
      IsSelected := SameText(C.ID, FSelectedID);

      if StepComps <> nil then
      begin
        if StepComps.IndexOf(C.ID) < 0 then Continue;
        IsInCurrentStep := (CurrStepComps <> nil) and (CurrStepComps.IndexOf(C.ID) >= 0);
      end
      else
        IsInCurrentStep := False;

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

      HasCollision := IsPartColliding(C.ID);

      LabelStr := C.ID;
      if DOF.Status = adsFixed then
        LabelStr := '(f) ' + LabelStr
      else if DOF.Status = adsUnderdefined then
        LabelStr := '(-) ' + LabelStr;

      RenderBox3D(Pos, C.Size, ColorForKind(C.Kind), IsSelected, HasCollision, IsInCurrentStep, LabelStr);

      if IsSelected then
        DrawDOFArrows(C.ID, Pos, C.Size, DOF);
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
end;

function TMechanicalAssemblyCanvas.HitTest(SX, SY: Integer): string;
var
  I: Integer;
  C: TAssemblyComponent;
  Pos: TAssemblyVec3;
  P: array[0..7] of TPoint;
  MinX, MaxX, MinY, MaxY: Integer;
begin
  Result := '';
  if FProject = nil then Exit;
  for I := FProject.ComponentCount - 1 downto 0 do
  begin
    C := FProject.Component(I);
    if FSolver <> nil then
      Pos := FSolver.GetSolvedPosition(C.ID)
    else
      Pos := C.Position;

    ProjectToScreen(Pos.X, Pos.Y, Pos.Z, P[0].X, P[0].Y);
    ProjectToScreen(Pos.X + C.Size.X, Pos.Y + C.Size.Y, Pos.Z + C.Size.Z, P[6].X, P[6].Y);
    MinX := Min(P[0].X, P[6].X) - 10;
    MaxX := Max(P[0].X, P[6].X) + 10;
    MinY := Min(P[0].Y, P[6].Y) - 10;
    MaxY := Max(P[0].Y, P[6].Y) + 10;
    if (SX >= MinX) and (SX <= MaxX) and (SY >= MinY) and (SY <= MaxY) then
      Exit(C.ID);
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
