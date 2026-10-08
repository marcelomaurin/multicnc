unit routerpcb_preview;

{ Previa do RouterPCB, em coordenadas de saida (as mesmas do G-code): zero no
  canto inferior esquerdo da placa, Y para cima, Bottom ja espelhado.

  Camadas desenhadas (cada uma pode ser desligada):
  - placa (contorno) e cobre do lado escolhido (Top vermelho, Bottom verde,
    as cores do LaserPCB/MakePCB), a partir das mascaras do projeto;
  - isolacao (azul), furos (cor por broca), furos fresados (laranja);
  - recorte (roxo) com as pontes destacadas (ambar);
  - pontos de folga menor que a fresa (circulos vermelhos);
  - grade de sondagem (pontos coloridos pela altura medida).
  Reguas em mm no topo e a esquerda. Roda do mouse = zoom no cursor;
  arrastar = mover; duplo clique = ajustar a placa. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, LCLType, LCLIntf,
  laserpcb_geom, laserpcb_drill, routerpcb_types, routerpcb_project,
  routerpcb_drillmap, routerpcb_cutout, routerpcb_heightmap;

const
  RP_RULER = 24;

type
  TRPPreview = class(TCustomControl)
  private
    FProject: TRouterPCBProject;
    FHeightMap: TRPHeightMap;
    FZoom, FOffX, FOffY: Double;     { px/mm; posicao na tela do zero }
    FCopper: TBitmap;                { cobre + placa em coordenadas de saida }
    FCacheValid: Boolean;
    FCachePxMM: Double;
    FDragging: Boolean;
    FDragX, FDragY: Integer;
    FFitPending: Boolean;
    procedure BuildCache;
    procedure DrawRulers;
    procedure DrawPaths(const P: TLPPaths; C: TColor; W: Integer);
    procedure DrawPath(const P: TLPPath; C: TColor; W: Integer);
    procedure DrawCircleMM(X, Y, D: Double; Fill, Line: TColor);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure DblClick; override;
  public
    ShowCopper, ShowIsolation, ShowDrills, ShowCutout, ShowLevel: Boolean;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { chamar depois de importar/gerar: refaz o desenho do cobre }
    procedure InvalidateCache;
    procedure FitBoard;
    procedure ZoomBy(F: Double; CX, CY: Integer);
    procedure ZoomIn;
    procedure ZoomOut;
    function ScreenPoint(X, Y: Double): TPoint;
    procedure ToWorld(PX, PY: Integer; out X, Y: Double);
    property Project: TRouterPCBProject read FProject write FProject;
    property HeightMap: TRPHeightMap read FHeightMap write FHeightMap;
    property Zoom: Double read FZoom;
  end;

function RPCopperColor(Side: TRPSide): TColor;
function RPDrillColor(Index: Integer): TColor;

implementation

const
  BOARD_FILL: TColor = $00E7EEE0;        { RGB(224,238,231) }
  ISO_COLOR: TColor = $00EB6325;         { RGB(37,99,235) }
  CUT_COLOR: TColor = $00ED3A7C;         { RGB(124,58,237) }
  TAB_COLOR: TColor = $000B9EF5;         { RGB(245,158,11) }
  MILL_COLOR: TColor = $000C58EA;        { RGB(234,88,12) }
  ISSUE_COLOR: TColor = $002626DC;       { RGB(220,38,38) }

function RPCopperColor(Side: TRPSide): TColor;
begin
  if Side = rsTop then Result := RGBToColor(205, 72, 62) else Result := RGBToColor(46, 150, 92);
end;

function RPDrillColor(Index: Integer): TColor;
const
  Pal: array[0..5] of LongWord = ($1F2937, $0F766E, $7C3AED, $B45309, $BE185D, $1D4ED8);
var V: LongWord;
begin
  V := Pal[Index mod Length(Pal)];
  Result := RGBToColor((V shr 16) and $FF, (V shr 8) and $FF, V and $FF);
end;

{ ---------------- TRPPreview ---------------- }

constructor TRPPreview.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  DoubleBuffered := True;
  Color := RGBToColor(246, 247, 249);
  ShowCopper := True; ShowIsolation := True; ShowDrills := True; ShowCutout := True; ShowLevel := True;
  FZoom := 8; FOffX := 60; FOffY := 300;
  FFitPending := True;
end;

destructor TRPPreview.Destroy;
begin
  FCopper.Free;
  inherited Destroy;
end;

procedure TRPPreview.InvalidateCache;
begin
  FCacheValid := False;
  Invalidate;
end;

function TRPPreview.ScreenPoint(X, Y: Double): TPoint;
begin
  Result.X := Round(FOffX + X * FZoom);
  Result.Y := Round(FOffY - Y * FZoom);
end;

procedure TRPPreview.ToWorld(PX, PY: Integer; out X, Y: Double);
begin
  X := (PX - FOffX) / FZoom;
  Y := (FOffY - PY) / FZoom;
end;

procedure TRPPreview.FitBoard;
var W, H, AW, AH: Double;
begin
  FFitPending := False;
  if (FProject = nil) or (FProject.BoardWidth <= 0) then
  begin
    W := 100; H := 80;
  end
  else
  begin
    W := FProject.BoardWidth; H := FProject.BoardHeight;
  end;
  AW := Max(50, ClientWidth - RP_RULER - 40);
  AH := Max(50, ClientHeight - RP_RULER - 40);
  FZoom := EnsureRange(Min(AW / (W + 6), AH / (H + 6)), 0.5, 400);
  FOffX := RP_RULER + 20 + (AW - W * FZoom) / 2;
  FOffY := RP_RULER + 20 + (AH + H * FZoom) / 2;
  Invalidate;
end;

procedure TRPPreview.ZoomBy(F: Double; CX, CY: Integer);
var X, Y, Z: Double;
begin
  ToWorld(CX, CY, X, Y);
  Z := EnsureRange(FZoom * F, 0.5, 400);
  FZoom := Z;
  FOffX := CX - X * FZoom;
  FOffY := CY + Y * FZoom;
  Invalidate;
end;

procedure TRPPreview.ZoomIn;
begin
  ZoomBy(1.25, ClientWidth div 2, ClientHeight div 2);
end;

procedure TRPPreview.ZoomOut;
begin
  ZoomBy(0.8, ClientWidth div 2, ClientHeight div 2);
end;

procedure TRPPreview.Resize;
begin
  inherited Resize;
  if FFitPending and (ClientWidth > 100) then FitBoard;
end;

procedure TRPPreview.BuildCache;
var W, H, X, Y: Integer; OX, OY, DX, DY, PxMM: Double; B: TLPRect; Board, Cop: Boolean;
  CB, CC, CBg: TColor; Line: PByte; Step, RI, GI, BI: Integer;

  procedure Put(P: PByte; C: TColor);
  var V: LongInt;
  begin
    V := ColorToRGB(C);
    P[RI] := V and $FF;
    P[GI] := (V shr 8) and $FF;
    P[BI] := (V shr 16) and $FF;
    if Step = 4 then P[3] := 255;
  end;

begin
  FCacheValid := True;
  FreeAndNil(FCopper);
  if (FProject = nil) or (FProject.BoardMask = nil) or (FProject.BoardWidth <= 0) then Exit;
  B := FProject.Bounds;
  { 1 pixel do cache = 1 pixel da mascara (no maximo 2500 px no lado maior) }
  PxMM := Min(1 / FProject.BoardMask.Res, 2500 / Max(FProject.BoardWidth, FProject.BoardHeight));
  W := Max(1, Ceil(FProject.BoardWidth * PxMM));
  H := Max(1, Ceil(FProject.BoardHeight * PxMM));
  FCachePxMM := PxMM;
  FCopper := TBitmap.Create;
  FCopper.PixelFormat := pf24bit;
  FCopper.SetSize(W, H);
  Step := FCopper.RawImage.Description.BitsPerPixel div 8;
  RI := FCopper.RawImage.Description.RedShift div 8;
  GI := FCopper.RawImage.Description.GreenShift div 8;
  BI := FCopper.RawImage.Description.BlueShift div 8;
  CB := BOARD_FILL; CC := RPCopperColor(FProject.Side); CBg := Color;
  FCopper.BeginUpdate;
  try
    for Y := 0 to H - 1 do
    begin
      Line := FCopper.ScanLine[Y];
      OY := (H - 1 - Y + 0.5) / PxMM;              { saida }
      DY := OY + B.MinY;                            { projeto }
      for X := 0 to W - 1 do
      begin
        OX := (X + 0.5) / PxMM;
        if FProject.Mirrored then DX := B.MaxX - OX else DX := OX + B.MinX;
        Board := FProject.BoardMask.Get(FProject.BoardMask.ColOf(DX), FProject.BoardMask.RowOf(DY)) <> 0;
        Cop := Board and (FProject.CopperMask <> nil) and
          (FProject.CopperMask.Get(FProject.CopperMask.ColOf(DX), FProject.CopperMask.RowOf(DY)) <> 0);
        if Cop then Put(@Line[X * Step], CC)
        else if Board then Put(@Line[X * Step], CB)
        else Put(@Line[X * Step], CBg);
      end;
    end;
  finally
    FCopper.EndUpdate;
  end;
end;

procedure TRPPreview.DrawPath(const P: TLPPath; C: TColor; W: Integer);
var J: Integer; Q: TPoint; Pts: array of TPoint;
begin
  if Length(P) < 2 then Exit;
  SetLength(Pts, Length(P));
  for J := 0 to High(P) do
  begin
    Q := ScreenPoint(P[J].X, P[J].Y);
    Pts[J] := Q;
  end;
  Canvas.Pen.Color := C;
  Canvas.Pen.Width := W;
  Canvas.Polyline(Pts);
end;

procedure TRPPreview.DrawPaths(const P: TLPPaths; C: TColor; W: Integer);
var I: Integer;
begin
  for I := 0 to High(P) do DrawPath(P[I], C, W);
end;

procedure TRPPreview.DrawCircleMM(X, Y, D: Double; Fill, Line: TColor);
var C: TPoint; R: Integer;
begin
  C := ScreenPoint(X, Y);
  R := Max(2, Round(D / 2 * FZoom));
  Canvas.Pen.Width := 1;
  Canvas.Pen.Color := Line;
  if Fill = clNone then Canvas.Brush.Style := bsClear
  else
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := Fill;
  end;
  Canvas.Ellipse(C.X - R, C.Y - R, C.X + R + 1, C.Y + R + 1);
  Canvas.Brush.Style := bsSolid;
end;

procedure TRPPreview.DrawRulers;
var StepMM, V, X, Y: Double; P: TPoint; S: string; Major: Integer;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := RGBToColor(255, 255, 255);
  Canvas.Pen.Color := RGBToColor(226, 232, 240);
  Canvas.Pen.Width := 1;
  Canvas.Rectangle(0, 0, ClientWidth, RP_RULER);
  Canvas.Rectangle(0, 0, RP_RULER, ClientHeight);
  Canvas.Font.Size := 7;
  Canvas.Font.Color := RGBToColor(100, 116, 139);
  StepMM := 1;
  while StepMM * FZoom < 8 do
    if StepMM < 5 then StepMM := 5 else StepMM := StepMM * 2;
  Major := 10;
  if StepMM >= 5 then Major := 2;
  Canvas.Pen.Color := RGBToColor(148, 163, 184);
  { topo }
  ToWorld(RP_RULER, 0, X, Y);
  V := Floor(X / StepMM) * StepMM;
  while True do
  begin
    P := ScreenPoint(V, 0);
    if P.X > ClientWidth then Break;
    if P.X >= RP_RULER then
    begin
      if Round(V / StepMM) mod Major = 0 then
      begin
        Canvas.Line(P.X, RP_RULER - 10, P.X, RP_RULER);
        S := IntToStr(Round(V));
        Canvas.TextOut(P.X + 2, 2, S);
      end
      else Canvas.Line(P.X, RP_RULER - 4, P.X, RP_RULER);
    end;
    V := V + StepMM;
  end;
  { esquerda }
  ToWorld(0, ClientHeight, X, Y);
  V := Floor(Y / StepMM) * StepMM;
  while True do
  begin
    P := ScreenPoint(0, V);
    if P.Y < RP_RULER then Break;
    if P.Y <= ClientHeight then
    begin
      if Round(V / StepMM) mod Major = 0 then
      begin
        Canvas.Line(RP_RULER - 10, P.Y, RP_RULER, P.Y);
        Canvas.TextOut(2, P.Y - 12, IntToStr(Round(V)));
      end
      else Canvas.Line(RP_RULER - 4, P.Y, RP_RULER, P.Y);
    end;
    V := V + StepMM;
  end;
  Canvas.Brush.Color := RGBToColor(255, 255, 255);
  Canvas.Pen.Color := RGBToColor(226, 232, 240);
  Canvas.Rectangle(0, 0, RP_RULER, RP_RULER);
  Canvas.TextOut(4, 6, 'mm');
end;

procedure TRPPreview.Paint;
var R: TRect; A, B: TPoint; I, J, K: Integer; G: TLPDrillGroup; H: TLPDrillHole;
  T: TRPTab; C: TRPCutContour; Seg: TLPPath; S, L: Double; MinH, MaxH, HH, F: Double;
  Pt: TPoint; Q: TLPPoint;

  function PointAt(const P: TLPPath; Dist: Double): TLPPoint;
  var N: Integer; Acc, D: Double;
  begin
    Acc := 0;
    for N := 1 to High(P) do
    begin
      D := LPDist(P[N-1], P[N]);
      if Acc + D >= Dist then
      begin
        if D < 1e-12 then Exit(P[N]);
        Exit(LPPoint(P[N-1].X + (P[N].X - P[N-1].X) * (Dist - Acc) / D,
          P[N-1].Y + (P[N].Y - P[N-1].Y) * (Dist - Acc) / D));
      end;
      Acc := Acc + D;
    end;
    Result := P[High(P)];
  end;

begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);
  if (FProject <> nil) and not FCacheValid then BuildCache;
  if FProject = nil then Exit;
  { placa e cobre }
  if FCopper <> nil then
  begin
    A := ScreenPoint(0, FProject.BoardHeight);
    B := ScreenPoint(FProject.BoardWidth, 0);
    R := Rect(A.X, A.Y, B.X, B.Y);
    if ShowCopper then Canvas.StretchDraw(R, FCopper)
    else
    begin
      Canvas.Brush.Color := BOARD_FILL;
      Canvas.FillRect(R);
    end;
  end;
  DrawPaths(FProject.OutputOutline, RGBToColor(71, 85, 105), 1);
  { isolacao }
  if ShowIsolation then DrawPaths(FProject.IsolationPaths, ISO_COLOR, 1);
  { recorte }
  if ShowCutout then
  begin
    for I := 0 to High(FProject.Cutouts) do
    begin
      C := FProject.Cutouts[I];
      DrawPath(C.Path, CUT_COLOR, Max(1, Min(Round(FProject.Cutout.ToolDiameter * FZoom * 0.25), 4)));
      for J := 0 to High(C.Tabs) do
      begin
        T := C.Tabs[J];
        Seg := nil;
        L := T.S1 - T.S0;
        for K := 0 to 8 do
        begin
          S := T.S0 + L * K / 8;
          Q := PointAt(C.Path, S);
          LPAddPoint(Seg, Q.X, Q.Y);
        end;
        DrawPath(Seg, TAB_COLOR, Max(3, Round(FProject.Cutout.ToolDiameter * FZoom * 0.6)));
      end;
    end;
    for I := 0 to High(FProject.MilledHoles) do
      DrawCircleMM(FProject.MilledHoles[I].X, FProject.MilledHoles[I].Y, FProject.MilledHoles[I].Diameter,
        clNone, MILL_COLOR);
  end;
  { furos }
  if ShowDrills then
    for I := 0 to FProject.DrillPlan.GroupCount - 1 do
    begin
      G := FProject.DrillPlan.Group(I);
      for J := 0 to High(G.Holes) do
      begin
        H := G.Holes[J];
        if H.Slot then
        begin
          Seg := nil;
          LPAddPoint(Seg, H.X, H.Y); LPAddPoint(Seg, H.X2, H.Y2);
          DrawPath(Seg, RPDrillColor(I), Max(2, Round(G.Diameter * FZoom)));
        end
        else DrawCircleMM(H.X, H.Y, G.Diameter, RPDrillColor(I), RPDrillColor(I));
      end;
    end;
  { folga menor que a fresa }
  for I := 0 to High(FProject.ClearanceIssues) do
  begin
    Pt := ScreenPoint(FProject.ClearanceIssues[I].X, FProject.ClearanceIssues[I].Y);
    Canvas.Pen.Color := ISSUE_COLOR; Canvas.Pen.Width := 2; Canvas.Brush.Style := bsClear;
    Canvas.Ellipse(Pt.X - 9, Pt.Y - 9, Pt.X + 10, Pt.Y + 10);
    Canvas.Brush.Style := bsSolid;
  end;
  { grade de sondagem }
  if ShowLevel and (FHeightMap <> nil) and FHeightMap.Ready and FProject.Level.Enabled then
  begin
    FHeightMap.Range(MinH, MaxH);
    for J := 0 to FHeightMap.Rows - 1 do
      for I := 0 to FHeightMap.Cols - 1 do
      begin
        Pt := ScreenPoint(FHeightMap.PointX(I), FHeightMap.PointY(J));
        if FHeightMap.Measured(I, J) and FHeightMap.Complete then
        begin
          HH := FHeightMap.GetZ(I, J) - FHeightMap.GetZ(0, 0);
          if MaxH - MinH > 1e-6 then F := (HH - MinH) / (MaxH - MinH) else F := 0.5;
          Canvas.Brush.Color := RGBToColor(Round(37 + F * 200), Round(99 + (1 - Abs(F - 0.5) * 2) * 80), Round(235 - F * 200));
          Canvas.Pen.Color := clWhite;
          Canvas.Rectangle(Pt.X - 5, Pt.Y - 5, Pt.X + 6, Pt.Y + 6);
          if FZoom > 6 then
          begin
            Canvas.Brush.Style := bsClear;
            Canvas.Font.Size := 7;
            Canvas.Font.Color := RGBToColor(30, 41, 59);
            Canvas.TextOut(Pt.X + 7, Pt.Y - 6, FormatFloat('0.000', HH));
            Canvas.Brush.Style := bsSolid;
          end;
        end
        else
        begin
          Canvas.Brush.Style := bsClear;
          Canvas.Pen.Color := RGBToColor(37, 99, 235);
          Canvas.Pen.Width := 1;
          Canvas.Ellipse(Pt.X - 4, Pt.Y - 4, Pt.X + 5, Pt.Y + 5);
          Canvas.Brush.Style := bsSolid;
        end;
      end;
  end;
  { zero da maquina }
  Pt := ScreenPoint(0, 0);
  Canvas.Pen.Width := 2;
  Canvas.Pen.Color := RGBToColor(220, 38, 38);
  Canvas.Line(Pt.X, Pt.Y, Pt.X + 18, Pt.Y);
  Canvas.Pen.Color := RGBToColor(22, 163, 74);
  Canvas.Line(Pt.X, Pt.Y, Pt.X, Pt.Y - 18);
  Canvas.Pen.Width := 1;
  DrawRulers;
end;

procedure TRPPreview.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if CanFocus then SetFocus;
  if Button in [mbLeft, mbMiddle] then
  begin
    FDragging := True;
    FDragX := X; FDragY := Y;
  end;
end;

procedure TRPPreview.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FDragging then
  begin
    FOffX := FOffX + (X - FDragX);
    FOffY := FOffY + (Y - FDragY);
    FDragX := X; FDragY := Y;
    Invalidate;
  end;
end;

procedure TRPPreview.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragging := False;
end;

function TRPPreview.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  if WheelDelta > 0 then ZoomBy(1.2, MousePos.X, MousePos.Y)
  else ZoomBy(1 / 1.2, MousePos.X, MousePos.Y);
  Result := True;
end;

procedure TRPPreview.DblClick;
begin
  inherited DblClick;
  FitBoard;
end;

end.
