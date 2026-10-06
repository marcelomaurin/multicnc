unit multicnc_print3d_view;

{ Visualizacao 3D do SimuCNC.

  Cada tipo de equipamento tem geometria e comportamento proprios:

  - Impressora 3D (Marlin): estilo "bed-slinger" (tipo Ender-3). A mesa
    aquecida e a peca impressa se movem em Y; o cabecote se move em X e o
    portico em Z. Hotend com bloco aquecedor que muda de cor conforme a
    temperatura e bico de latao com a ponta exatamente em XYZ. Material
    depositado em camadas.
  - CNC Router (GRBL): portico movel em Y, carro X/Z, motor do spindle e
    fresa. Mesa de sacrificio (MDF) com bloco de madeira; os sulcos tem a
    largura da fresa e escurecem com a profundidade. Movimento abaixo da
    superficie com o spindle desligado e marcado como colisao.
  - CNC Laser (GRBL): quadro aberto, mesa colmeia e chapa de compensado.
    Modulo laser no portico; feixe e brilho quando ha potencia. Queima
    mais escura quanto maior a potencia.

  Renderizacao: projecao ortografica com camera orbital (arrastar = girar,
  botao direito = mover, roda = zoom, duplo clique = restaurar), faces com
  iluminacao direcional, remocao de faces ocultas e ordenacao por
  profundidade (pintor). }

{$mode objfpc}{$H+}

interface

uses
  multisuite_numfmt, Classes, SysUtils, Controls, Graphics, Math, Types,
  aimarlinsimulator;

type
  TSimMachineKind = (smkPrinter, smkRouter, smkLaser);
  TSegmentKind = (sgExtrude, sgLaser, sgCut, sgCrash);

  TPrintSegment = record
    A, B: TAIMarlinPosition;
    { >0 material extrudado ou potencia do spindle; <0 queima de laser (-potencia) }
    Material: Double;
    Kind: TSegmentKind;
  end;

  TPrint3DView = class(TCustomControl)
  private type
    TPrim = record
      Pts: array of TPoint;
      Color, PenColor: TColor;
      Depth: Double;
      IsLine: Boolean;
      Under: Boolean;
      Width: Integer;
    end;
  private
    FSegments: array of TPrintSegment;
    FSegCount: Integer;
    FCurrent: TAIMarlinPosition;
    FKind: TSimMachineKind;
    FShowFrame: Boolean;
    FVolumeX, FVolumeY, FVolumeZ: Double;
    FRotX, FRotZ, FZoom, FPanX, FPanY: Double;
    FDrag, FPan: Boolean;
    FLastX, FLastY: Integer;
    FToolPower: Double;
    FRapid: Boolean;
    FHotend, FHotendTarget, FBed, FBedTarget: Double;
    FInfoTitle: string;
    FStockTop: Double;
    FStockTopSet: Boolean;
    FToolDiameter: Double;
    FCrashCount: Integer;
    { camera calculada em cada quadro }
    FCZ, FSZ, FCX, FSX, FScale: Double;
    FOrigin: TPoint;
    FCenter: TAIMarlinPosition;
    FPrims: array of TPrim;
    FPrimCount: Integer;
    FUnder: Boolean;  { primitivas da base: sempre desenhadas primeiro }
    procedure SetShowFrame(Value: Boolean);
    function GetSegmentCount: Integer;
    function GetLaserMode: Boolean;
    procedure SetLaserMode(Value: Boolean);
    procedure SetKind(Value: TSimMachineKind);
    function GetStockTop: Double;
    procedure SetStockTop(Value: Double);
    procedure AppendSegment(const A, B: TAIMarlinPosition; AMaterial: Double; AKind: TSegmentKind);
    { camera / projecao }
    procedure SetupCamera(W, H: Integer);
    function P3(X, Y, Z: Double): TAIMarlinPosition;
    function ProjectXYZ(X, Y, Z: Double): TPoint;
    function DepthXYZ(X, Y, Z: Double): Double;
    procedure Project(const P: TAIMarlinPosition; out Q: TPoint);
    { cena }
    procedure ClearPrims;
    procedure AddFace(const V: array of TAIMarlinPosition; NX, NY, NZ: Double; AColor: TColor);
    procedure AddBox(X1, Y1, Z1, X2, Y2, Z2: Double; AColor: TColor);
    procedure AddCylinder(CX, CY, Z1, Z2, R: Double; Sides: Integer; AColor: TColor);
    procedure AddCone(CX, CY, ZBase, ZTip, R: Double; Sides: Integer; AColor: TColor);
    procedure AddLine3(X1, Y1, Z1, X2, Y2, Z2: Double; AColor: TColor; AWidth: Integer);
    procedure BuildPrinter;
    procedure BuildRouter;
    procedure BuildLaser;
    procedure DrawWorkLayer(ACanvas: TCanvas);
    procedure DrawPrinterWork(ACanvas: TCanvas);
    procedure DrawRouterWork(ACanvas: TCanvas);
    procedure DrawLaserWork(ACanvas: TCanvas);
    procedure DrawBuildVolume(ACanvas: TCanvas; DY: Double);
    procedure DrawPrims(ACanvas: TCanvas; APivot: Double; ADrawWork: Boolean);
    procedure DrawBoxDirect(ACanvas: TCanvas; X1, Y1, Z1, X2, Y2, Z2: Double; AColor: TColor);
    procedure DrawHUD(ACanvas: TCanvas);
    procedure DrawGizmo(ACanvas: TCanvas);
    function WorkPivotDepth: Double;
    function BedOffsetY: Double;
  protected
    procedure Paint; override;
    procedure DblClick; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure RenderScene(ACanvas: TCanvas);
    procedure ClearPrint;
    procedure AddMotion(Sender: TObject; const A, B: TAIMarlinPosition; Material: Double);
    procedure AddLaserMotion(const A, B: TAIMarlinPosition; Power: Double);
    { Router: Power = potencia do spindle (S) no momento do movimento }
    procedure AddCutMotion(const A, B: TAIMarlinPosition; Power: Double; Rapid: Boolean);
    procedure SetPosition(const P: TAIMarlinPosition);
    procedure SetToolState(Power: Double; Rapid: Boolean);
    procedure SetTemperatures(Hotend, HotendTarget, Bed, BedTarget: Double);
    procedure ResetView;
    procedure TopView;
    procedure FrontView;
    procedure SetBuildVolume(X, Y, Z: Double);
    function Segment(I: Integer): TPrintSegment;
    property ShowFrame: Boolean read FShowFrame write SetShowFrame;
    property LaserMode: Boolean read GetLaserMode write SetLaserMode;
    property MachineKind: TSimMachineKind read FKind write SetKind;
    property InfoTitle: string read FInfoTitle write FInfoTitle;
    { Router: altura (Z fisico) da superficie do bloco. Padrao: 1/3 do curso Z }
    property StockTop: Double read GetStockTop write SetStockTop;
    property ToolDiameter: Double read FToolDiameter write FToolDiameter;
    property CrashCount: Integer read FCrashCount;
    property VolumeX: Double read FVolumeX;
    property VolumeY: Double read FVolumeY;
    property VolumeZ: Double read FVolumeZ;
    property SegmentCount: Integer read GetSegmentCount;
    property CurrentPosition: TAIMarlinPosition read FCurrent;
  end;

implementation

const
  { direcao da luz (normalizada) }
  LX = -0.35; LY = -0.45; LZ = 0.82;

function Mix(A, B: TColor; T: Double): TColor;
var
  CA, CB: TColor;
begin
  T := EnsureRange(T, 0, 1);
  CA := ColorToRGB(A);
  CB := ColorToRGB(B);
  Result := RGBToColor(
    Round(Red(CA) * T + Red(CB) * (1 - T)),
    Round(Green(CA) * T + Green(CB) * (1 - T)),
    Round(Blue(CA) * T + Blue(CB) * (1 - T)));
end;

function Shade(C: TColor; F: Double): TColor;
var
  RGB: TColor;
begin
  RGB := ColorToRGB(C);
  Result := RGBToColor(
    Min(255, Round(Red(RGB) * F)),
    Min(255, Round(Green(RGB) * F)),
    Min(255, Round(Blue(RGB) * F)));
end;

{ ---------------------------------------------------------------------------- }

constructor TPrint3DView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Color := RGBToColor(17, 20, 27);
  FVolumeX := 220; FVolumeY := 220; FVolumeZ := 250;
  FRotX := 56; FRotZ := 28; FZoom := 1.0;
  FToolDiameter := 3.175;
  FKind := smkPrinter;
  FBed := 25; FHotend := 25;
  DoubleBuffered := True;
end;

procedure TPrint3DView.SetBuildVolume(X, Y, Z: Double);
begin
  if (X > 0) and (Y > 0) and (Z > 0) then
  begin
    FVolumeX := X; FVolumeY := Y; FVolumeZ := Z;
    Invalidate;
  end;
end;

function TPrint3DView.GetSegmentCount: Integer;
begin
  Result := FSegCount;
end;

function TPrint3DView.Segment(I: Integer): TPrintSegment;
begin
  if (I < 0) or (I >= FSegCount) then
    raise ERangeError.CreateFmt('Segment index %d out of range', [I]);
  Result := FSegments[I];
end;

function TPrint3DView.GetLaserMode: Boolean;
begin
  Result := FKind = smkLaser;
end;

procedure TPrint3DView.SetLaserMode(Value: Boolean);
begin
  if Value then
    SetKind(smkLaser)
  else if FKind = smkLaser then
    SetKind(smkPrinter);
end;

procedure TPrint3DView.SetKind(Value: TSimMachineKind);
begin
  if FKind = Value then
    Exit;
  FKind := Value;
  ClearPrint;
end;

function TPrint3DView.GetStockTop: Double;
begin
  if FStockTopSet then
    Result := FStockTop
  else
    Result := Max(2, Min(20, FVolumeZ / 3));
end;

procedure TPrint3DView.SetStockTop(Value: Double);
begin
  if Value <= 0 then
  begin
    FStockTopSet := False;
    Exit;
  end;
  if FStockTopSet and SameValue(FStockTop, Value, 0.001) then
    Exit;
  FStockTop := Value;
  FStockTopSet := True;
  Invalidate;
end;

procedure TPrint3DView.SetShowFrame(Value: Boolean);
begin
  FShowFrame := Value;
  Invalidate;
end;

procedure TPrint3DView.ClearPrint;
begin
  SetLength(FSegments, 0);
  FSegCount := 0;
  FCrashCount := 0;
  FillChar(FCurrent, SizeOf(FCurrent), 0);
  Invalidate;
end;

procedure TPrint3DView.AppendSegment(const A, B: TAIMarlinPosition;
  AMaterial: Double; AKind: TSegmentKind);
begin
  if FSegCount >= Length(FSegments) then
    SetLength(FSegments, Max(256, Length(FSegments) * 2));
  FSegments[FSegCount].A := A;
  FSegments[FSegCount].B := B;
  FSegments[FSegCount].Material := AMaterial;
  FSegments[FSegCount].Kind := AKind;
  Inc(FSegCount);
end;

procedure TPrint3DView.AddMotion(Sender: TObject; const A, B: TAIMarlinPosition;
  Material: Double);
begin
  FCurrent := B;
  if Material > 0 then
    AppendSegment(A, B, Material, sgExtrude);
  Invalidate;
end;

procedure TPrint3DView.AddLaserMotion(const A, B: TAIMarlinPosition; Power: Double);
begin
  FCurrent := B;
  if Power > 0 then
    AppendSegment(A, B, -Power, sgLaser);
  Invalidate;
end;

procedure TPrint3DView.AddCutMotion(const A, B: TAIMarlinPosition; Power: Double;
  Rapid: Boolean);
begin
  FCurrent := B;
  if Power > 0 then
    AppendSegment(A, B, Power, sgCut)
  else if (Max(A.Z, B.Z) < StockTop - 0.01) and
          (Hypot(B.X - A.X, B.Y - A.Y) > 0.01) then
  begin
    { deslocamento lateral dentro do material com o spindle parado.
      Movimentos so em Z (ex.: subir a ferramenta) nao contam. }
    AppendSegment(A, B, 0, sgCrash);
    Inc(FCrashCount);
  end;
  Invalidate;
end;

procedure TPrint3DView.SetPosition(const P: TAIMarlinPosition);
begin
  FCurrent := P;
  Invalidate;
end;

procedure TPrint3DView.SetToolState(Power: Double; Rapid: Boolean);
begin
  FToolPower := Power;
  FRapid := Rapid;
end;

procedure TPrint3DView.SetTemperatures(Hotend, HotendTarget, Bed, BedTarget: Double);
begin
  FHotend := Hotend; FHotendTarget := HotendTarget;
  FBed := Bed; FBedTarget := BedTarget;
end;

procedure TPrint3DView.ResetView;
begin
  FRotX := 56; FRotZ := 28; FZoom := 1.0; FPanX := 0; FPanY := 0;
  Invalidate;
end;

procedure TPrint3DView.TopView;
begin
  FRotX := 0; FRotZ := 0; FPanX := 0; FPanY := 0;
  Invalidate;
end;

procedure TPrint3DView.FrontView;
begin
  FRotX := 88; FRotZ := 0; FPanX := 0; FPanY := 0;
  Invalidate;
end;

{ ---------------------------------------------------------------------------- }
{ Camera                                                                       }

procedure TPrint3DView.SetupCamera(W, H: Integer);
var
  Ext, MachineH: Double;
begin
  FCZ := Cos(DegToRad(FRotZ)); FSZ := Sin(DegToRad(FRotZ));
  FCX := Cos(DegToRad(FRotX)); FSX := Sin(DegToRad(FRotX));
  case FKind of
    smkPrinter: MachineH := FVolumeZ + 70;
    smkRouter:  MachineH := FVolumeZ + 150;
  else
    MachineH := 90;
  end;
  Ext := Max(Max(FVolumeX + 100, FVolumeY + 100), MachineH * 1.15);
  if FKind = smkPrinter then
    Ext := Max(FVolumeX + 140, (FVolumeZ + 110) * 1.3);
  FScale := Min(W, H) / Ext * 0.92 * FZoom;
  if FKind = smkPrinter then
    FCenter := P3(FVolumeX / 2, FVolumeY / 2, MachineH * 0.40)
  else
    FCenter := P3(FVolumeX / 2, FVolumeY / 2, MachineH * 0.32);
  FOrigin := Point(W div 2 + Round(FPanX), H div 2 + 18 + Round(FPanY));
end;

function TPrint3DView.P3(X, Y, Z: Double): TAIMarlinPosition;
begin
  Result.X := X; Result.Y := Y; Result.Z := Z; Result.E := 0;
end;

function TPrint3DView.ProjectXYZ(X, Y, Z: Double): TPoint;
var
  U, V: Double;
begin
  X := X - FCenter.X; Y := Y - FCenter.Y; Z := Z - FCenter.Z;
  { Convencao CNC: frente da maquina em Y = 0, Y cresce para o fundo, Z
    para cima. RotX: 0 = vista de topo, 90 = vista frontal. }
  U := X * FCZ + Y * FSZ;
  V := -X * FSZ + Y * FCZ;
  Result.X := FOrigin.X + Round(U * FScale);
  Result.Y := FOrigin.Y - Round((V * FCX + Z * FSX) * FScale);
end;

{ Proximidade do observador (maior = mais perto) }
function TPrint3DView.DepthXYZ(X, Y, Z: Double): Double;
begin
  Result := -(-X * FSZ + Y * FCZ) * FSX + Z * FCX;
end;

procedure TPrint3DView.Project(const P: TAIMarlinPosition; out Q: TPoint);
begin
  Q := ProjectXYZ(P.X, P.Y, P.Z);
end;

{ ---------------------------------------------------------------------------- }
{ Primitivas                                                                   }

procedure TPrint3DView.ClearPrims;
begin
  FPrimCount := 0;
end;

procedure TPrint3DView.AddFace(const V: array of TAIMarlinPosition;
  NX, NY, NZ: Double; AColor: TColor);
var
  I, N: Integer;
  Facing, Light, CX, CY, CZ: Double;
begin
  N := Length(V);
  if N < 3 then
    Exit;
  { remocao de faces voltadas para tras }
  Facing := NX * FSZ * FSX - NY * FCZ * FSX + NZ * FCX;
  if Facing <= 0.001 then
    Exit;
  Light := NX * LX + NY * LY + NZ * LZ;
  if FPrimCount >= Length(FPrims) then
    SetLength(FPrims, Max(64, Length(FPrims) * 2));
  with FPrims[FPrimCount] do
  begin
    SetLength(Pts, N);
    CX := 0; CY := 0; CZ := 0;
    for I := 0 to N - 1 do
    begin
      Pts[I] := ProjectXYZ(V[I].X, V[I].Y, V[I].Z);
      CX := CX + V[I].X; CY := CY + V[I].Y; CZ := CZ + V[I].Z;
    end;
    Depth := DepthXYZ(CX / N, CY / N, CZ / N);
    Color := Shade(AColor, 0.58 + 0.42 * Max(0, Light) + 0.06 * Facing);
    PenColor := Color;
    IsLine := False;
    Under := FUnder;
    Width := 1;
  end;
  Inc(FPrimCount);
end;

procedure TPrint3DView.AddBox(X1, Y1, Z1, X2, Y2, Z2: Double; AColor: TColor);
begin
  AddFace([P3(X1, Y1, Z2), P3(X2, Y1, Z2), P3(X2, Y2, Z2), P3(X1, Y2, Z2)], 0, 0, 1, AColor);
  AddFace([P3(X1, Y1, Z1), P3(X1, Y2, Z1), P3(X2, Y2, Z1), P3(X2, Y1, Z1)], 0, 0, -1, AColor);
  AddFace([P3(X1, Y1, Z1), P3(X2, Y1, Z1), P3(X2, Y1, Z2), P3(X1, Y1, Z2)], 0, -1, 0, AColor);
  AddFace([P3(X2, Y2, Z1), P3(X1, Y2, Z1), P3(X1, Y2, Z2), P3(X2, Y2, Z2)], 0, 1, 0, AColor);
  AddFace([P3(X1, Y2, Z1), P3(X1, Y1, Z1), P3(X1, Y1, Z2), P3(X1, Y2, Z2)], -1, 0, 0, AColor);
  AddFace([P3(X2, Y1, Z1), P3(X2, Y2, Z1), P3(X2, Y2, Z2), P3(X2, Y1, Z2)], 1, 0, 0, AColor);
end;

procedure TPrint3DView.AddCylinder(CX, CY, Z1, Z2, R: Double; Sides: Integer;
  AColor: TColor);
var
  I: Integer;
  A0, A1, AM: Double;
  Cap: array of TAIMarlinPosition;
begin
  SetLength(Cap, Sides);
  for I := 0 to Sides - 1 do
  begin
    A0 := 2 * Pi * I / Sides;
    A1 := 2 * Pi * (I + 1) / Sides;
    AM := (A0 + A1) / 2;
    AddFace([P3(CX + R * Cos(A0), CY + R * Sin(A0), Z1),
             P3(CX + R * Cos(A1), CY + R * Sin(A1), Z1),
             P3(CX + R * Cos(A1), CY + R * Sin(A1), Z2),
             P3(CX + R * Cos(A0), CY + R * Sin(A0), Z2)],
      Cos(AM), Sin(AM), 0, AColor);
    Cap[I] := P3(CX + R * Cos(-A0), CY + R * Sin(-A0), Z1);
  end;
  AddFace(Cap, 0, 0, -1, AColor);
  for I := 0 to Sides - 1 do
    Cap[I] := P3(CX + R * Cos(2 * Pi * I / Sides), CY + R * Sin(2 * Pi * I / Sides), Z2);
  AddFace(Cap, 0, 0, 1, AColor);
end;

procedure TPrint3DView.AddCone(CX, CY, ZBase, ZTip, R: Double; Sides: Integer;
  AColor: TColor);
var
  I: Integer;
  A0, A1, AM, H, NZ: Double;
  Cap: array of TAIMarlinPosition;
begin
  H := Abs(ZBase - ZTip);
  if H < 0.001 then
    Exit;
  NZ := R / Sqrt(R * R + H * H);
  if ZTip < ZBase then
    NZ := -NZ;
  SetLength(Cap, Sides);
  for I := 0 to Sides - 1 do
  begin
    A0 := 2 * Pi * I / Sides;
    A1 := 2 * Pi * (I + 1) / Sides;
    AM := (A0 + A1) / 2;
    AddFace([P3(CX + R * Cos(A0), CY + R * Sin(A0), ZBase),
             P3(CX + R * Cos(A1), CY + R * Sin(A1), ZBase),
             P3(CX, CY, ZTip)],
      Cos(AM) * (1 - Abs(NZ)), Sin(AM) * (1 - Abs(NZ)), NZ, AColor);
    Cap[I] := P3(CX + R * Cos(A0), CY + R * Sin(A0), ZBase);
  end;
  if ZTip < ZBase then
    AddFace(Cap, 0, 0, 1, AColor);
end;

procedure TPrint3DView.AddLine3(X1, Y1, Z1, X2, Y2, Z2: Double; AColor: TColor;
  AWidth: Integer);
begin
  if FPrimCount >= Length(FPrims) then
    SetLength(FPrims, Max(64, Length(FPrims) * 2));
  with FPrims[FPrimCount] do
  begin
    SetLength(Pts, 2);
    Pts[0] := ProjectXYZ(X1, Y1, Z1);
    Pts[1] := ProjectXYZ(X2, Y2, Z2);
    Depth := DepthXYZ((X1 + X2) / 2, (Y1 + Y2) / 2, (Z1 + Z2) / 2);
    Color := AColor;
    PenColor := AColor;
    IsLine := True;
    Under := FUnder;
    Width := AWidth;
  end;
  Inc(FPrimCount);
end;

{ ---------------------------------------------------------------------------- }
{ Maquinas                                                                     }

function TPrint3DView.BedOffsetY: Double;
begin
  { bed-slinger: a mesa anda em Y para que o bico fique sempre em Y = VY/2 }
  if FKind = smkPrinter then
    Result := FVolumeY / 2 - FCurrent.Y
  else
    Result := 0;
end;

procedure TPrint3DView.BuildPrinter;
var
  X, Z, HY, DY, Heat, BedHeat: Double;
  Alu, Dark, BedCol, BlockCol: TColor;
begin
  X := FCurrent.X; Z := FCurrent.Z;
  HY := FVolumeY / 2;           { Y fixo do cabecote no mundo }
  DY := BedOffsetY;
  Alu := RGBToColor(96, 104, 118);
  Dark := RGBToColor(38, 42, 50);

  { base (fixa), trilho Y e mesa: camada inferior }
  FUnder := True;
  AddBox(-60, -40, -62, FVolumeX + 60, FVolumeY + 40, -44, Dark);
  AddBox(FVolumeX / 2 - 30, -38, -44, FVolumeX / 2 - 10, FVolumeY + 38, -34, Alu);
  AddBox(FVolumeX / 2 + 10, -38, -44, FVolumeX / 2 + 30, FVolumeY + 38, -34, Alu);

  { mesa aquecida (move em Y): avermelha com a temperatura }
  BedHeat := EnsureRange((FBed - 30) / 70, 0, 1);
  BedCol := Mix(RGBToColor(150, 40, 28), RGBToColor(32, 34, 40), BedHeat * 0.85);
  AddBox(FVolumeX / 2 - 50, DY + FVolumeY / 2 - 50, -34, FVolumeX / 2 + 50, DY + FVolumeY / 2 + 50, -10, Dark);
  AddBox(-10, DY - 10, -10, FVolumeX + 10, DY + FVolumeY + 10, -1, BedCol);
  FUnder := False;

  { colunas Z e travessa superior (atras do bico) }
  AddBox(-46, HY + 30, -44, -26, HY + 50, FVolumeZ + 60, Alu);
  AddBox(FVolumeX + 26, HY + 30, -44, FVolumeX + 46, HY + 50, FVolumeZ + 60, Alu);
  AddBox(-46, HY + 30, FVolumeZ + 60, FVolumeX + 46, HY + 50, FVolumeZ + 78, Alu);

  { portico X (sobe e desce com Z) }
  AddBox(-36, HY + 16, Z + 30, FVolumeX + 36, HY + 30, Z + 46, RGBToColor(130, 140, 156));
  AddBox(-52, HY + 12, Z + 22, -26, HY + 54, Z + 58, Dark);
  AddBox(FVolumeX + 26, HY + 12, Z + 22, FVolumeX + 52, HY + 54, Z + 58, Dark);

  { carro X + hotend }
  AddBox(X - 24, HY + 8, Z + 18, X + 24, HY + 16, Z + 60, RGBToColor(52, 58, 70));
  AddCylinder(X, HY, Z + 15, Z + 42, 9, 12, RGBToColor(176, 182, 192));      { dissipador }
  Heat := EnsureRange((FHotend - 40) / 180, 0, 1);
  BlockCol := Mix(RGBToColor(235, 82, 32), RGBToColor(150, 154, 160), Heat);
  AddBox(X - 8, HY - 7, Z + 6, X + 8, HY + 9, Z + 15, BlockCol);              { bloco aquecedor }
  AddCone(X, HY, Z + 6, Z, 4.2, 10, RGBToColor(214, 166, 64));                { bico de latao }
  AddBox(X + 11, HY - 14, Z + 8, X + 26, HY + 6, Z + 36, RGBToColor(28, 30, 36)); { ventoinha }
  AddBox(X - 16, HY - 15, Z + 4, X + 11, HY - 11, Z + 12, RGBToColor(28, 30, 36)); { duto }
end;

procedure TPrint3DView.BuildRouter;
var
  X, Y, Z, GTop, BitR: Double;
  Alu, Dark, Gantry, SpindleRing: TColor;
begin
  X := FCurrent.X; Y := FCurrent.Y; Z := FCurrent.Z;
  GTop := FVolumeZ + 60;
  Alu := RGBToColor(140, 150, 166);
  Dark := RGBToColor(44, 50, 62);
  Gantry := RGBToColor(38, 72, 140);

  { base, trilhos Y e mesa de sacrificio (MDF) }
  FUnder := True;
  AddBox(-60, -45, -48, FVolumeX + 60, FVolumeY + 45, -26, Dark);
  AddBox(-56, -45, -26, -34, FVolumeY + 45, -14, Alu);
  AddBox(FVolumeX + 34, -45, -26, FVolumeX + 56, FVolumeY + 45, -14, Alu);
  AddBox(-26, -30, -26, FVolumeX + 26, FVolumeY + 30, -1, RGBToColor(186, 152, 108));
  FUnder := False;

  { portico (move em Y): laterais, viga e trilho X atras do spindle }
  AddBox(-64, Y - 34, -22, -36, Y + 70, GTop, Gantry);
  AddBox(FVolumeX + 36, Y - 34, -22, FVolumeX + 64, Y + 70, GTop, Gantry);
  AddBox(-64, Y + 44, GTop - 34, FVolumeX + 64, Y + 70, GTop, Alu);
  AddBox(-64, Y + 44, GTop - 58, FVolumeX + 64, Y + 54, GTop - 48, Alu);

  { carro X (fixo em Z) e placa Z (sobe e desce) }
  AddBox(X - 34, Y + 34, GTop - 70, X + 34, Y + 44, GTop + 6, Dark);
  AddBox(X - 30, Y + 28, Z + 30, X + 30, Y + 34, Z + 112, RGBToColor(160, 170, 186));

  { spindle centrado em (X, Y): motor, anel de estado, pinca e fresa }
  AddCylinder(X, Y, Z + 42, Z + 118, 26, 16, RGBToColor(40, 44, 52));
  if FToolPower > 0 then
    SpindleRing := RGBToColor(34, 197, 94)
  else
    SpindleRing := RGBToColor(100, 110, 124);
  AddCylinder(X, Y, Z + 100, Z + 106, 27, 16, SpindleRing);
  AddCylinder(X, Y, Z + 32, Z + 42, 12, 12, RGBToColor(196, 202, 212));
  BitR := Max(0.8, FToolDiameter / 2);
  AddCylinder(X, Y, Z + 2, Z + 32, BitR, 8, RGBToColor(206, 210, 220));
  AddCone(X, Y, Z + 2, Z, BitR, 8, RGBToColor(230, 230, 236));
end;

procedure TPrint3DView.BuildLaser;
var
  X, Y, K: Double;
  I: Integer;
  Alu, Dark: TColor;
begin
  X := FCurrent.X; Y := FCurrent.Y;
  Alu := RGBToColor(120, 130, 146);
  Dark := RGBToColor(30, 32, 38);

  { quadro aberto e mesa colmeia }
  FUnder := True;
  AddBox(-58, -48, -34, -34, FVolumeY + 48, -10, Alu);
  AddBox(FVolumeX + 34, -48, -34, FVolumeX + 58, FVolumeY + 48, -10, Alu);
  AddBox(-58, -48, -34, FVolumeX + 58, -26, -10, Alu);
  AddBox(-58, FVolumeY + 26, -34, FVolumeX + 58, FVolumeY + 48, -10, Alu);
  { mesa colmeia }
  AddBox(-14, -14, -26, FVolumeX + 14, FVolumeY + 14, -5, RGBToColor(70, 74, 82));
  FUnder := False;

  { portico (move em Y) }
  AddBox(-66, Y - 20, -14, -32, Y + 44, 36, Dark);
  AddBox(FVolumeX + 32, Y - 20, -14, FVolumeX + 66, Y + 44, 36, Dark);
  AddBox(-60, Y + 18, 16, FVolumeX + 60, Y + 40, 36, Alu);

  { modulo laser (move em X) }
  AddBox(X - 20, Y + 10, 14, X + 20, Y + 18, 70, Dark);                    { placa do carro }
  AddBox(X - 17, Y - 15, 22, X + 17, Y + 10, 78, RGBToColor(24, 24, 28));  { corpo }
  K := 0;
  for I := 0 to 5 do
  begin
    AddBox(X - 17, Y - 17, 34 + K, X + 17, Y - 15, 37 + K, RGBToColor(150, 158, 172)); { aletas }
    K := K + 7;
  end;
  AddCylinder(X, Y - 2, 78, 84, 13, 14, RGBToColor(40, 40, 46));           { ventoinha }
  AddCylinder(X, Y, 10, 22, 6, 12, RGBToColor(176, 182, 192));             { lente }
  AddCone(X, Y, 10, 6, 6, 12, RGBToColor(204, 160, 70));                   { bocal }
end;

{ ---------------------------------------------------------------------------- }
{ Trabalho (mesa, peca e trajetoria)                                           }

procedure TPrint3DView.DrawBuildVolume(ACanvas: TCanvas; DY: Double);
var
  C: array[0..7] of TPoint;
  procedure E(A, B: Integer);
  begin
    ACanvas.Line(C[A], C[B]);
  end;
begin
  C[0] := ProjectXYZ(0, DY, 0);
  C[1] := ProjectXYZ(FVolumeX, DY, 0);
  C[2] := ProjectXYZ(FVolumeX, DY + FVolumeY, 0);
  C[3] := ProjectXYZ(0, DY + FVolumeY, 0);
  C[4] := ProjectXYZ(0, DY, FVolumeZ);
  C[5] := ProjectXYZ(FVolumeX, DY, FVolumeZ);
  C[6] := ProjectXYZ(FVolumeX, DY + FVolumeY, FVolumeZ);
  C[7] := ProjectXYZ(0, DY + FVolumeY, FVolumeZ);
  ACanvas.Pen.Width := 1;
  ACanvas.Pen.Style := psDot;
  ACanvas.Pen.Color := RGBToColor(96, 165, 250);
  ACanvas.Brush.Style := bsClear;
  E(0, 1); E(1, 2); E(2, 3); E(3, 0);
  E(4, 5); E(5, 6); E(6, 7); E(7, 4);
  E(0, 4); E(1, 5); E(2, 6); E(3, 7);
  ACanvas.Pen.Style := psSolid;
  ACanvas.Brush.Style := bsSolid;
end;

procedure TPrint3DView.DrawPrinterWork(ACanvas: TCanvas);
var
  I, G, W: Integer;
  DY, Layer: Double;
  PA, PB: TPoint;
  Fil: TColor;
begin
  DY := BedOffsetY;
  { grade da mesa }
  ACanvas.Pen.Width := 1;
  ACanvas.Pen.Color := Mix(RGBToColor(120, 124, 134), RGBToColor(60, 62, 70), 0.5);
  for G := 0 to 10 do
  begin
    ACanvas.Line(ProjectXYZ(G * FVolumeX / 10, DY, 0), ProjectXYZ(G * FVolumeX / 10, DY + FVolumeY, 0));
    ACanvas.Line(ProjectXYZ(0, DY + G * FVolumeY / 10, 0), ProjectXYZ(FVolumeX, DY + G * FVolumeY / 10, 0));
  end;
  if FShowFrame then
    DrawBuildVolume(ACanvas, DY);

  { filamento: camadas alternam levemente o tom }
  W := Max(2, Round(0.6 * FScale));
  ACanvas.Pen.Width := W;
  Fil := RGBToColor(249, 115, 22);
  for I := 0 to FSegCount - 1 do
    with FSegments[I] do
      if Kind = sgExtrude then
      begin
        Layer := Round(B.Z * 5);
        if Odd(Round(Layer)) then
          ACanvas.Pen.Color := Shade(Fil, 0.86)
        else
          ACanvas.Pen.Color := Fil;
        PA := ProjectXYZ(A.X, A.Y + DY, A.Z);
        PB := ProjectXYZ(B.X, B.Y + DY, B.Z);
        ACanvas.Line(PA, PB);
      end;
  ACanvas.Pen.Width := 1;
end;

procedure TPrint3DView.DrawRouterWork(ACanvas: TCanvas);
var
  I, W: Integer;
  STop, Depth: Double;
  Wood: TColor;
  Q: array[0..3] of TPoint;
begin
  STop := StockTop;
  Wood := RGBToColor(222, 184, 135);

  { bloco de madeira: faces visiveis desenhadas aqui para ficar sob os sulcos }
  DrawBoxDirect(ACanvas, 4, 4, 0, FVolumeX - 4, FVolumeY - 4, STop, Wood);

  { veios da madeira }
  ACanvas.Pen.Width := 1;
  ACanvas.Pen.Color := Shade(Wood, 0.9);
  I := 0;
  while I < Round(FVolumeY) do
  begin
    ACanvas.Line(ProjectXYZ(4, I + 6, STop), ProjectXYZ(FVolumeX - 4, I + 9, STop));
    Inc(I, 11);
  end;
  if FShowFrame then
    DrawBuildVolume(ACanvas, 0);

  { sulcos: largura da fresa, mais escuros conforme a profundidade }
  W := Max(2, Round(FToolDiameter * FScale));
  for I := 0 to FSegCount - 1 do
    with FSegments[I] do
    begin
      if Kind = sgCut then
      begin
        Depth := STop - Min(A.Z, B.Z);
        if Depth <= 0.01 then
          Continue;
        ACanvas.Pen.Width := W;
        ACanvas.Pen.Color := Mix(RGBToColor(92, 56, 24), Shade(Wood, 0.78),
          EnsureRange(Depth / Max(1, STop), 0.15, 1));
        ACanvas.Line(ProjectXYZ(A.X, A.Y, STop), ProjectXYZ(B.X, B.Y, STop));
      end
      else if Kind = sgCrash then
      begin
        ACanvas.Pen.Width := Max(2, W div 2);
        ACanvas.Pen.Color := RGBToColor(239, 68, 68);
        ACanvas.Line(ProjectXYZ(A.X, A.Y, STop), ProjectXYZ(B.X, B.Y, STop));
      end;
    end;
  ACanvas.Pen.Width := 1;

  { sombra/marcador da ferramenta sobre a peca }
  Q[0] := ProjectXYZ(FCurrent.X - 3, FCurrent.Y - 3, STop);
  Q[1] := ProjectXYZ(FCurrent.X + 3, FCurrent.Y - 3, STop);
  Q[2] := ProjectXYZ(FCurrent.X + 3, FCurrent.Y + 3, STop);
  Q[3] := ProjectXYZ(FCurrent.X - 3, FCurrent.Y + 3, STop);
  if FCurrent.Z >= STop then
  begin
    ACanvas.Brush.Color := Shade(Wood, 0.7);
    ACanvas.Pen.Color := Shade(Wood, 0.7);
    ACanvas.Polygon(Q);
  end;
end;

procedure TPrint3DView.DrawLaserWork(ACanvas: TCanvas);
var
  I, W, G: Integer;
  Ply, Burn: TColor;
  Pw: Double;
begin
  Ply := RGBToColor(226, 194, 146);
  DrawBoxDirect(ACanvas, 0, 0, -5, FVolumeX, FVolumeY, 0, Ply);
  { regua nas bordas da chapa (a cada 10 mm, marca maior a cada 50 mm) }
  ACanvas.Pen.Width := 1;
  ACanvas.Pen.Color := Shade(Ply, 0.8);
  G := 0;
  while G <= Round(FVolumeX) do
  begin
    if G mod 50 = 0 then
      ACanvas.Line(ProjectXYZ(G, 0, 0), ProjectXYZ(G, 8, 0))
    else
      ACanvas.Line(ProjectXYZ(G, 0, 0), ProjectXYZ(G, 4, 0));
    Inc(G, 10);
  end;
  G := 0;
  while G <= Round(FVolumeY) do
  begin
    if G mod 50 = 0 then
      ACanvas.Line(ProjectXYZ(0, G, 0), ProjectXYZ(8, G, 0))
    else
      ACanvas.Line(ProjectXYZ(0, G, 0), ProjectXYZ(4, G, 0));
    Inc(G, 10);
  end;
  if FShowFrame then
    DrawBuildVolume(ACanvas, 0);

  W := Max(1, Round(0.2 * FScale));
  ACanvas.Pen.Width := W;
  for I := 0 to FSegCount - 1 do
    with FSegments[I] do
      if Kind = sgLaser then
      begin
        Pw := EnsureRange(-Material / 1000, 0.08, 1);
        Burn := Mix(RGBToColor(30, 16, 8), Shade(Ply, 0.82), 0.35 + 0.65 * Pw);
        ACanvas.Pen.Color := Burn;
        ACanvas.Line(ProjectXYZ(A.X, A.Y, 0.05), ProjectXYZ(B.X, B.Y, 0.05));
      end;
  ACanvas.Pen.Width := 1;
end;

{ Caixa convexa desenhada imediatamente (sem usar a lista de primitivas):
  as faces visiveis de uma caixa nunca se sobrepoem. }
procedure TPrint3DView.DrawBoxDirect(ACanvas: TCanvas; X1, Y1, Z1, X2, Y2, Z2: Double;
  AColor: TColor);

  procedure F(const V: array of TAIMarlinPosition; NX, NY, NZ: Double);
  var
    Pts: array of TPoint;
    I: Integer;
    Facing, Light: Double;
  begin
    Facing := NX * FSZ * FSX - NY * FCZ * FSX + NZ * FCX;
    if Facing <= 0.001 then
      Exit;
    Light := NX * LX + NY * LY + NZ * LZ;
    SetLength(Pts, Length(V));
    for I := 0 to High(V) do
      Pts[I] := ProjectXYZ(V[I].X, V[I].Y, V[I].Z);
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := Shade(AColor, 0.58 + 0.42 * Max(0, Light) + 0.06 * Facing);
    ACanvas.Pen.Width := 1;
    ACanvas.Pen.Color := ACanvas.Brush.Color;
    ACanvas.Polygon(Pts);
  end;

begin
  F([P3(X1, Y1, Z2), P3(X2, Y1, Z2), P3(X2, Y2, Z2), P3(X1, Y2, Z2)], 0, 0, 1);
  F([P3(X1, Y1, Z1), P3(X1, Y2, Z1), P3(X2, Y2, Z1), P3(X2, Y1, Z1)], 0, 0, -1);
  F([P3(X1, Y1, Z1), P3(X2, Y1, Z1), P3(X2, Y1, Z2), P3(X1, Y1, Z2)], 0, -1, 0);
  F([P3(X2, Y2, Z1), P3(X1, Y2, Z1), P3(X1, Y2, Z2), P3(X2, Y2, Z2)], 0, 1, 0);
  F([P3(X1, Y2, Z1), P3(X1, Y1, Z1), P3(X1, Y1, Z2), P3(X1, Y2, Z2)], -1, 0, 0);
  F([P3(X2, Y1, Z1), P3(X2, Y2, Z1), P3(X2, Y2, Z2), P3(X2, Y1, Z2)], 1, 0, 0);
end;

procedure TPrint3DView.DrawWorkLayer(ACanvas: TCanvas);
begin
  case FKind of
    smkPrinter: DrawPrinterWork(ACanvas);
    smkRouter:  DrawRouterWork(ACanvas);
    smkLaser:   DrawLaserWork(ACanvas);
  end;
end;

function TPrint3DView.WorkPivotDepth: Double;
begin
  case FKind of
    smkRouter: Result := DepthXYZ(FVolumeX / 2, FVolumeY / 2, StockTop) + 0.5;
    smkLaser:  Result := DepthXYZ(FVolumeX / 2, FVolumeY / 2, 0) + 0.5;
  else
    Result := DepthXYZ(FVolumeX / 2, FVolumeY / 2 + BedOffsetY, 0) + 0.5;
  end;
end;

{ Desenha as primitivas em ordem de profundidade. A camada de trabalho
  (mesa, peca, trajetoria) e intercalada na profundidade APivot: o que
  esta atras dela e pintado antes, o que esta a frente, depois. }
procedure TPrint3DView.DrawPrims(ACanvas: TCanvas; APivot: Double; ADrawWork: Boolean);
var
  Order: array of Integer;
  I, J: Integer;
  WorkDone: Boolean;

  procedure DrawOne(K: Integer);
  begin
    with FPrims[K] do
      if IsLine then
      begin
        ACanvas.Pen.Width := Width;
        ACanvas.Pen.Color := Color;
        ACanvas.Line(Pts[0], Pts[1]);
      end
      else
      begin
        ACanvas.Pen.Width := 1;
        ACanvas.Pen.Color := PenColor;
        ACanvas.Brush.Style := bsSolid;
        ACanvas.Brush.Color := Color;
        ACanvas.Polygon(Pts);
      end;
  end;

  procedure Sort(L, R: Integer);
  var
    A, B, Pv: Integer;
    D: Double;
  begin
    A := L; B := R;
    D := FPrims[Order[(L + R) shr 1]].Depth;
    repeat
      while FPrims[Order[A]].Depth < D do Inc(A);
      while FPrims[Order[B]].Depth > D do Dec(B);
      if A <= B then
      begin
        Pv := Order[A]; Order[A] := Order[B]; Order[B] := Pv;
        Inc(A); Dec(B);
      end;
    until A > B;
    if L < B then Sort(L, B);
    if A < R then Sort(A, R);
  end;

begin
  SetLength(Order, FPrimCount);
  for I := 0 to FPrimCount - 1 do
    Order[I] := I;
  if FPrimCount > 1 then
    Sort(0, FPrimCount - 1);
  { 1a passada: base da maquina, na ordem em que foi montada (de baixo para
    cima); 2a: o resto por profundidade, intercalando o trabalho }
  for J := 0 to FPrimCount - 1 do
    if FPrims[J].Under then
      DrawOne(J);
  WorkDone := not ADrawWork;
  for J := 0 to FPrimCount - 1 do
  begin
    I := Order[J];
    if FPrims[I].Under then
      Continue;
    if (not WorkDone) and (FPrims[I].Depth > APivot) then
    begin
      DrawWorkLayer(ACanvas);
      WorkDone := True;
    end;
    DrawOne(I);
  end;
  if not WorkDone then
    DrawWorkLayer(ACanvas);
end;

{ ---------------------------------------------------------------------------- }
{ HUD                                                                          }

procedure TPrint3DView.DrawGizmo(ACanvas: TCanvas);
var
  C: TPoint;
  procedure Axis(X, Y, Z: Double; Col: TColor; const S: string);
  var
    U, V: Double;
    P: TPoint;
  begin
    U := X * FCZ + Y * FSZ;
    V := -((-X * FSZ + Y * FCZ) * FCX + Z * FSX);
    P := Point(C.X + Round(U * 26), C.Y + Round(V * 26));
    ACanvas.Pen.Width := 2;
    ACanvas.Pen.Color := Col;
    ACanvas.Line(C, P);
    ACanvas.Brush.Style := bsClear;
    ACanvas.Font.Color := Col;
    ACanvas.TextOut(P.X + Round(U * 8) - 4, P.Y + Round(V * 8) - 8, S);
  end;
begin
  C := Point(ClientWidth - 52, 56);
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := RGBToColor(30, 36, 48);
  ACanvas.Pen.Color := RGBToColor(51, 65, 85);
  ACanvas.Pen.Width := 1;
  ACanvas.Ellipse(C.X - 40, C.Y - 40, C.X + 40, C.Y + 40);
  ACanvas.Font.Size := 9;
  ACanvas.Font.Style := [fsBold];
  Axis(1, 0, 0, RGBToColor(248, 113, 113), 'X');
  Axis(0, 1, 0, RGBToColor(74, 222, 128), 'Y');
  Axis(0, 0, 1, RGBToColor(96, 165, 250), 'Z');
  ACanvas.Font.Style := [];
end;

procedure TPrint3DView.DrawHUD(ACanvas: TCanvas);
var
  R: TRect;
  Title, Pos, ToolTxt: string;
  ToolCol: TColor;
  Y, W: Integer;
begin
  Title := FInfoTitle;
  if Title = '' then
    case FKind of
      smkPrinter: Title := 'Impressora 3D';
      smkRouter:  Title := 'CNC Router';
      smkLaser:   Title := 'CNC Laser';
    end;

  case FKind of
    smkPrinter:
      begin
        Pos := Format('Bico  X %.2f   Y %.2f   Z %.2f mm', [FCurrent.X, FCurrent.Y, FCurrent.Z], InvariantFS);
        ToolTxt := Format('Bico %.0f/%.0f °C    Mesa %.0f/%.0f °C',
          [FHotend, FHotendTarget, FBed, FBedTarget], InvariantFS);
        if FHotendTarget > 0 then
          ToolCol := RGBToColor(251, 146, 60)
        else
          ToolCol := RGBToColor(148, 163, 184);
      end;
    smkRouter:
      begin
        Pos := Format('Fresa  X %.2f   Y %.2f   Z %.2f mm', [FCurrent.X, FCurrent.Y, FCurrent.Z], InvariantFS);
        if FToolPower > 0 then
        begin
          ToolTxt := Format('Spindle LIGADO  S%.0f    Prof. %.2f mm',
            [FToolPower, Max(0, StockTop - FCurrent.Z)], InvariantFS);
          ToolCol := RGBToColor(74, 222, 128);
        end
        else
        begin
          ToolTxt := Format('Spindle desligado    Superficie Z %.1f mm', [StockTop], InvariantFS);
          ToolCol := RGBToColor(148, 163, 184);
        end;
      end;
  else
    begin
      Pos := Format('Laser  X %.2f   Y %.2f mm', [FCurrent.X, FCurrent.Y], InvariantFS);
      if (FToolPower > 0) and not FRapid then
      begin
        ToolTxt := Format('Laser LIGADO  S%.0f (%.0f%%)', [FToolPower, FToolPower / 10], InvariantFS);
        ToolCol := RGBToColor(196, 181, 253);
      end
      else
      begin
        ToolTxt := 'Laser desligado';
        ToolCol := RGBToColor(148, 163, 184);
      end;
    end;
  end;

  ACanvas.Font.Name := 'Segoe UI';
  ACanvas.Font.Size := 9;
  W := Max(ACanvas.TextWidth(Pos), ACanvas.TextWidth(ToolTxt)) + 32;
  W := Max(W, 260);
  R := Rect(14, 14, 14 + W, 14 + 96);
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := RGBToColor(30, 36, 48);
  ACanvas.Pen.Color := RGBToColor(51, 65, 85);
  ACanvas.Pen.Width := 1;
  ACanvas.RoundRect(R, 14, 14);
  ACanvas.Brush.Style := bsClear;
  Y := R.Top + 10;
  ACanvas.Font.Size := 11;
  ACanvas.Font.Style := [fsBold];
  ACanvas.Font.Color := clWhite;
  ACanvas.TextOut(R.Left + 16, Y, Title);
  Inc(Y, 24);
  ACanvas.Font.Size := 9;
  ACanvas.Font.Style := [];
  ACanvas.Font.Color := RGBToColor(203, 213, 225);
  ACanvas.TextOut(R.Left + 16, Y, Pos);
  Inc(Y, 19);
  ACanvas.Font.Style := [fsBold];
  ACanvas.Font.Color := ToolCol;
  ACanvas.TextOut(R.Left + 16, Y, ToolTxt);
  ACanvas.Font.Style := [];

  if (FKind = smkRouter) and (FCrashCount > 0) then
  begin
    ACanvas.Font.Style := [fsBold];
    Title := Format('COLISAO: fresa entrou na peca com o spindle desligado (%d trechos)', [FCrashCount]);
    W := ACanvas.TextWidth(Title) + 28;
    R := Rect((ClientWidth - W) div 2, ClientHeight - 82, (ClientWidth + W) div 2, ClientHeight - 52);
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := RGBToColor(127, 29, 29);
    ACanvas.Pen.Color := RGBToColor(239, 68, 68);
    ACanvas.RoundRect(R, 12, 12);
    ACanvas.Brush.Style := bsClear;
    ACanvas.Font.Color := RGBToColor(254, 226, 226);
    ACanvas.TextOut(R.Left + 14, R.Top + 7, Title);
    ACanvas.Font.Style := [];
  end;

  DrawGizmo(ACanvas);

  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Size := 8;
  ACanvas.Font.Color := RGBToColor(100, 116, 139);
  ACanvas.TextOut(16, ClientHeight - 40,
    'Arrastar: girar   |   Botao direito: mover   |   Roda: zoom   |   Duplo clique: restaurar');
  case FKind of
    smkPrinter: Title := Format('Mesa %.0f x %.0f mm  |  Altura %.0f mm  |  Laranja: filamento depositado  |  Trechos: %d',
      [FVolumeX, FVolumeY, FVolumeZ, FSegCount], InvariantFS);
    smkRouter: Title := Format('Mesa %.0f x %.0f mm  |  Curso Z %.0f mm  |  Fresa %.2f mm  |  Sulcos mais escuros = mais profundos  |  Trechos: %d',
      [FVolumeX, FVolumeY, FVolumeZ, FToolDiameter, FSegCount], InvariantFS);
  else
    Title := Format('Area %.0f x %.0f mm  |  Queima mais escura = mais potencia  |  Trechos: %d',
      [FVolumeX, FVolumeY, FSegCount], InvariantFS);
  end;
  ACanvas.TextOut(16, ClientHeight - 22, Title);
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Pen.Width := 1;
end;

{ ---------------------------------------------------------------------------- }

procedure TPrint3DView.Paint;
begin
  inherited Paint;
  RenderScene(Canvas);
end;

procedure TPrint3DView.RenderScene(ACanvas: TCanvas);
var
  R: TRect;
  Tip, Lens: TPoint;
  Glow: Integer;
  Floor: array[0..3] of TPoint;
  M: Double;
begin
  R := Rect(0, 0, ClientWidth, ClientHeight);
  ACanvas.GradientFill(R, RGBToColor(30, 36, 48), RGBToColor(13, 16, 22), gdVertical);
  if (ClientWidth < 10) or (ClientHeight < 10) then
    Exit;
  SetupCamera(ClientWidth, ClientHeight);

  { piso: sombra suave sob a maquina }
  M := 90;
  if FKind = smkPrinter then
  begin
    Floor[0] := ProjectXYZ(-M, -M - FVolumeY / 2, -64);
    Floor[1] := ProjectXYZ(FVolumeX + M, -M - FVolumeY / 2, -64);
    Floor[2] := ProjectXYZ(FVolumeX + M, FVolumeY * 1.5 + M, -64);
    Floor[3] := ProjectXYZ(-M, FVolumeY * 1.5 + M, -64);
  end
  else
  begin
    Floor[0] := ProjectXYZ(-M, -M, -50);
    Floor[1] := ProjectXYZ(FVolumeX + M, -M, -50);
    Floor[2] := ProjectXYZ(FVolumeX + M, FVolumeY + M, -50);
    Floor[3] := ProjectXYZ(-M, FVolumeY + M, -50);
  end;
  ACanvas.Pen.Color := RGBToColor(36, 44, 58);
  ACanvas.Brush.Color := RGBToColor(24, 29, 39);
  ACanvas.Polygon(Floor);

  ClearPrims;
  case FKind of
    smkPrinter: BuildPrinter;
    smkRouter:  BuildRouter;
    smkLaser:   BuildLaser;
  end;
  DrawPrims(ACanvas, WorkPivotDepth, True);

  { feixe do laser e ponto de queima }
  if (FKind = smkLaser) and (FToolPower > 0) and not FRapid then
  begin
    Lens := ProjectXYZ(FCurrent.X, FCurrent.Y, 6);
    Tip := ProjectXYZ(FCurrent.X, FCurrent.Y, 0);
    ACanvas.Pen.Width := 5;
    ACanvas.Pen.Color := RGBToColor(109, 40, 217);
    ACanvas.Line(Lens, Tip);
    ACanvas.Pen.Width := 2;
    ACanvas.Pen.Color := RGBToColor(221, 214, 254);
    ACanvas.Line(Lens, Tip);
    Glow := Max(6, Round(3 * FScale));
    ACanvas.Pen.Width := 1;
    ACanvas.Pen.Color := RGBToColor(139, 92, 246);
    ACanvas.Brush.Color := RGBToColor(139, 92, 246);
    ACanvas.Ellipse(Tip.X - Glow, Tip.Y - Glow div 2, Tip.X + Glow, Tip.Y + Glow div 2);
    ACanvas.Pen.Color := RGBToColor(237, 233, 254);
    ACanvas.Brush.Color := clWhite;
    ACanvas.Ellipse(Tip.X - Glow div 3, Tip.Y - Glow div 5, Tip.X + Glow div 3, Tip.Y + Glow div 5);
  end;

  { ponto exato da ferramenta }
  Tip := ProjectXYZ(FCurrent.X, FCurrent.Y + 0, FCurrent.Z);
  if FKind = smkPrinter then
    Tip := ProjectXYZ(FCurrent.X, FVolumeY / 2, FCurrent.Z)
  else if FKind = smkLaser then
    Tip := ProjectXYZ(FCurrent.X, FCurrent.Y, 0);
  ACanvas.Pen.Width := 1;
  ACanvas.Pen.Color := RGBToColor(250, 204, 21);
  ACanvas.Brush.Color := RGBToColor(250, 204, 21);
  ACanvas.Ellipse(Tip.X - 3, Tip.Y - 3, Tip.X + 4, Tip.Y + 4);

  DrawHUD(ACanvas);
end;

procedure TPrint3DView.DblClick;
begin
  inherited DblClick;
  ResetView;
end;

procedure TPrint3DView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
    FDrag := True
  else if Button = mbRight then
    FPan := True;
  if FDrag or FPan then
  begin
    MouseCapture := True;
    FLastX := X;
    FLastY := Y;
  end;
end;

procedure TPrint3DView.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FDrag then
  begin
    FRotZ := FRotZ - (X - FLastX) * 0.6;
    FRotX := EnsureRange(FRotX - (Y - FLastY) * 0.6, 0, 90);
    Invalidate;
  end
  else if FPan then
  begin
    FPanX := FPanX + (X - FLastX);
    FPanY := FPanY + (Y - FLastY);
    Invalidate;
  end;
  FLastX := X;
  FLastY := Y;
end;

procedure TPrint3DView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDrag := False;
  FPan := False;
  MouseCapture := False;
end;

function TPrint3DView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  Result := True;
  if WheelDelta > 0 then
    FZoom := Min(8, FZoom * 1.12)
  else
    FZoom := Max(0.3, FZoom / 1.12);
  Invalidate;
end;

end.
