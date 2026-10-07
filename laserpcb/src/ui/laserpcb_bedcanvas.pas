unit laserpcb_bedcanvas;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Math, Controls, Graphics, LCLType, laserpcb_layout;
type
  TLaserBedCanvas = class(TCustomControl)
  private
    FLayout: TLaserBedLayout;
    FSelected: Integer;
    FZoom, FSnap, FOX, FOY: Double;
    FDragging: Boolean;
    FStartX, FStartY: Integer;
    FItemX, FItemY: Double;
    FOnSelectionChanged, FOnLayoutChanged: TNotifyEvent;
    procedure SetLayout(AValue: TLaserBedLayout);
    procedure SetSelected(I: Integer);
    function HitTest(X, Y: Double): Integer;
    procedure FitRect(X, Y, W, H: Double);
    procedure ChangeZoom(Factor: Double);
  protected
    procedure Paint; override;
    procedure DrawItem(Item: TLaserLayoutItem); virtual;
    procedure DrawOverlay; virtual;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    function ScreenPoint(X, Y: Double): TPoint;
    procedure WorldPoint(PX, PY: Integer; out X, Y: Double);
    procedure FitBed;
    procedure FitBoards;
    procedure RotateSelected90;
    procedure ZoomIn;
    procedure ZoomOut;
    procedure LayoutChanged;
    property Layout: TLaserBedLayout read FLayout write SetLayout;
    property SelectedIndex: Integer read FSelected write SetSelected;
    property SnapMM: Double read FSnap write FSnap;
    property Zoom: Double read FZoom;
    property OnSelectionChanged: TNotifyEvent read FOnSelectionChanged write FOnSelectionChanged;
    property OnLayoutChanged: TNotifyEvent read FOnLayoutChanged write FOnLayoutChanged;
  end;
implementation
const
  { reguas em mm (estilo LightBurn/LaserArt) }
  RULER_W = 34;
  RULER_H = 20;
procedure DrawRulers(C: TCanvas; W, H: Integer; Zoom, OX, OY, Step: Double);
var V, First, Last: Double; P, I, Major: Integer; S: string;
begin
  C.Brush.Style := bsSolid; C.Brush.Color := RGBToColor(248,250,252);
  C.Pen.Color := RGBToColor(203,213,225);
  C.FillRect(0,0,W,RULER_H); C.FillRect(0,0,RULER_W,H);
  C.Line(0,RULER_H-1,W,RULER_H-1); C.Line(RULER_W-1,0,RULER_W-1,H);
  C.Font.Size := 7; C.Font.Color := RGBToColor(100,116,139); C.Brush.Style := bsClear;
  { rotulos a cada 1, 2, 5 ou 10 divisoes, com pelo menos 44 px entre eles }
  Major := 1;
  while (Major < 1000) and (Major*Step*Zoom < 44) do
    if Major = 1 then Major := 2 else if Major = 2 then Major := 5 else Major := Major*2;
  { superior: X }
  First := Floor(((RULER_W-OX)/Zoom)/Step); Last := Ceil(((W-OX)/Zoom)/Step);
  for I := Round(First) to Round(Last) do
  begin
    V := I*Step; P := Round(OX+V*Zoom);
    if P < RULER_W then Continue;
    if I mod Major = 0 then
    begin
      C.Line(P,RULER_H-10,P,RULER_H);
      S := FloatToStr(V); C.TextOut(P+2,1,S);
    end
    else C.Line(P,RULER_H-4,P,RULER_H);
  end;
  { esquerda: Y para cima }
  First := Floor(((OY-H)/Zoom)/Step); Last := Ceil(((OY-RULER_H)/Zoom)/Step);
  for I := Round(First) to Round(Last) do
  begin
    V := I*Step; P := Round(OY-V*Zoom);
    if P < RULER_H then Continue;
    if I mod Major = 0 then
    begin
      C.Line(RULER_W-10,P,RULER_W,P);
      S := FloatToStr(V); C.TextOut(2,P-12,S);
    end
    else C.Line(RULER_W-4,P,RULER_W,P);
  end;
  C.Brush.Style := bsSolid; C.Brush.Color := RGBToColor(241,245,249);
  C.FillRect(0,0,RULER_W-1,RULER_H-1);
  C.Brush.Style := bsClear; C.TextOut(8,4,'mm');
  C.Font.Size := 10;
end;
constructor TLaserBedCanvas.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSelected := -1; FZoom := 1; FSnap := 1; FOX := 24; FOY := 24;
  Color := RGBToColor(242,245,248); DoubleBuffered := True;
end;
procedure TLaserBedCanvas.SetLayout(AValue: TLaserBedLayout);
begin FLayout := AValue; FSelected := -1; FitBed; end;
procedure TLaserBedCanvas.SetSelected(I: Integer);
begin
  if (FLayout = nil) or (I >= FLayout.Count) or (I < -1) then I := -1;
  FSelected := I; Invalidate;
  if Assigned(FOnSelectionChanged) then FOnSelectionChanged(Self);
end;
function TLaserBedCanvas.ScreenPoint(X, Y: Double): TPoint;
begin Result := Point(Round(FOX+X*FZoom), Round(FOY-Y*FZoom)); end;
procedure TLaserBedCanvas.WorldPoint(PX, PY: Integer; out X, Y: Double);
begin X := (PX-FOX)/FZoom; Y := (FOY-PY)/FZoom; end;
procedure TLaserBedCanvas.FitRect(X, Y, W, H: Double);
begin
  if not FiniteNumber(W) or not FiniteNumber(H) or (W <= 0) or (H <= 0) then Exit;
  FZoom := EnsureRange(Min(Max(1,ClientWidth-RULER_W-56)/W, Max(1,ClientHeight-RULER_H-64)/H), 0.01, 100);
  FOX := RULER_W+(ClientWidth-RULER_W-W*FZoom)/2-X*FZoom;
  FOY := RULER_H+(ClientHeight-RULER_H+H*FZoom)/2+Y*FZoom;
  Invalidate;
end;
procedure TLaserBedCanvas.FitBed;
begin if FLayout <> nil then FitRect(0,0,FLayout.BedWidth,FLayout.BedHeight); end;
procedure TLaserBedCanvas.FitBoards;
var I: Integer; X0,Y0,X1,Y1: Double; P: TLaserLayoutItem;
begin
  if (FLayout = nil) or (FLayout.Count = 0) then begin FitBed; Exit; end;
  X0 := Infinity; Y0 := Infinity; X1 := NegInfinity; Y1 := NegInfinity;
  for I := 0 to FLayout.Count-1 do
  begin
    P := FLayout.Item(I);
    X0 := Min(X0,P.X); Y0 := Min(Y0,P.Y);
    X1 := Max(X1,P.X+P.PlacedWidth); Y1 := Max(Y1,P.Y+P.PlacedHeight);
  end;
  FitRect(X0-3,Y0-3,X1-X0+6,Y1-Y0+6);
end;
procedure TLaserBedCanvas.ChangeZoom(Factor: Double);
var X,Y: Double;
begin
  WorldPoint(ClientWidth div 2,ClientHeight div 2,X,Y);
  FZoom := EnsureRange(FZoom*Factor,0.01,100);
  FOX := ClientWidth/2-X*FZoom; FOY := ClientHeight/2+Y*FZoom; Invalidate;
end;
procedure TLaserBedCanvas.ZoomIn;
begin ChangeZoom(1.25); end;
procedure TLaserBedCanvas.ZoomOut;
begin ChangeZoom(0.8); end;
function TLaserBedCanvas.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  if WheelDelta > 0 then ZoomIn else ZoomOut;
  Result := True;
end;
function TLaserBedCanvas.HitTest(X,Y: Double): Integer;
var I: Integer; P: TLaserLayoutItem;
begin
  Result := -1; if FLayout = nil then Exit;
  for I := FLayout.Count-1 downto 0 do
  begin
    P := FLayout.Item(I);
    if (X >= P.X) and (Y >= P.Y) and (X <= P.X+P.PlacedWidth) and
      (Y <= P.Y+P.PlacedHeight) then Exit(I);
  end;
end;
procedure TLaserBedCanvas.DrawItem(Item: TLaserLayoutItem);
var A,B: TPoint;
begin
  A := ScreenPoint(Item.X,Item.Y+Item.PlacedHeight);
  B := ScreenPoint(Item.X+Item.PlacedWidth,Item.Y);
  Canvas.Brush.Color := clWhite; Canvas.Pen.Color := clSilver;
  Canvas.Rectangle(A.X,A.Y,B.X,B.Y);
end;
procedure TLaserBedCanvas.DrawOverlay;
begin end;
procedure TLaserBedCanvas.Paint;
var I: Integer; P: TLaserLayoutItem; A,B: TPoint; K: TKeepOut;
  X0,Y0,X1,Y1,Step: Double; First,Last: Integer;
begin
  Canvas.Brush.Style := bsSolid; Canvas.Brush.Color := Color; Canvas.FillRect(ClientRect);
  if FLayout = nil then Exit;
  WorldPoint(0,ClientHeight,X0,Y0); WorldPoint(ClientWidth,0,X1,Y1);
  Step := 10;
  while Step*FZoom < 16 do Step := Step*2;
  Canvas.Pen.Color := RGBToColor(225,231,236); Canvas.Pen.Width := 1;
  if FiniteNumber(FLayout.BedWidth) and FiniteNumber(FLayout.BedHeight) then
  begin
    First := Max(0,Ceil(X0/Step)); Last := Min(100000,Floor(Min(X1,FLayout.BedWidth)/Step));
    for I := First to Last do
    begin A := ScreenPoint(I*Step,0); B := ScreenPoint(I*Step,FLayout.BedHeight); Canvas.Line(A.X,A.Y,B.X,B.Y); end;
    First := Max(0,Ceil(Y0/Step)); Last := Min(100000,Floor(Min(Y1,FLayout.BedHeight)/Step));
    for I := First to Last do
    begin A := ScreenPoint(0,I*Step); B := ScreenPoint(FLayout.BedWidth,I*Step); Canvas.Line(A.X,A.Y,B.X,B.Y); end;
    A := ScreenPoint(0,FLayout.BedHeight); B := ScreenPoint(FLayout.BedWidth,0);
    Canvas.Pen.Color := RGBToColor(148,163,184); Canvas.Brush.Style := bsClear;
    Canvas.Rectangle(A.X,A.Y,B.X,B.Y);
  end;
  for I := 0 to FLayout.KeepOutCount-1 do
  begin
    K := FLayout.KeepOut(I); A := ScreenPoint(K.X,K.Y+K.Height); B := ScreenPoint(K.X+K.Width,K.Y);
    Canvas.Brush.Style := bsBDiagonal; Canvas.Brush.Color := RGBToColor(254,226,226);
    Canvas.Pen.Color := RGBToColor(220,38,38); Canvas.Rectangle(A.X,A.Y,B.X,B.Y);
  end;
  Canvas.Brush.Style := bsSolid;
  for I := 0 to FLayout.Count-1 do DrawItem(FLayout.Item(I));
  DrawOverlay;
  Canvas.Brush.Style := bsClear;
  for I := 0 to FLayout.Count-1 do
  begin
    P := FLayout.Item(I); A := ScreenPoint(P.X,P.Y+P.PlacedHeight); B := ScreenPoint(P.X+P.PlacedWidth,P.Y);
    if I = FSelected then begin Canvas.Pen.Color := RGBToColor(37,99,235); Canvas.Pen.Width := 2; end
    else begin Canvas.Pen.Color := RGBToColor(100,116,139); Canvas.Pen.Width := 1; end;
    Canvas.Rectangle(A.X,A.Y,B.X,B.Y);
    Canvas.Font.Color := RGBToColor(51,65,85);
    if P.Locked then Canvas.TextOut(A.X+4,A.Y-18,P.Name+' [travada]')
    else Canvas.TextOut(A.X+4,A.Y-18,P.Name);
  end;
  Canvas.Pen.Width := 1;
  DrawRulers(Canvas,ClientWidth,ClientHeight,FZoom,FOX,FOY,Step);
  Canvas.Brush.Style := bsSolid;
  Canvas.Font.Color := RGBToColor(100,116,139);
  Canvas.TextOut(RULER_W+8,ClientHeight-22,'mm  |  X →   Y ↑  |  grade '+FloatToStr(Step)+' mm');
  if FLayout.Count = 0 then
  begin
    Canvas.Font.Size := 14; Canvas.Font.Color := RGBToColor(100,116,139);
    Canvas.TextOut(Max(12,ClientWidth div 2-120),ClientHeight div 2,'Importe uma placa para comecar');
    Canvas.Font.Size := 10;
  end;
end;
procedure TLaserBedCanvas.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
var WX,WY: Double; P: TLaserLayoutItem;
begin
  inherited;
  if Button <> mbLeft then Exit;
  WorldPoint(X,Y,WX,WY); SetSelected(HitTest(WX,WY));
  FDragging := FSelected >= 0;
  FStartX := X; FStartY := Y;
  if FDragging then begin P := FLayout.Item(FSelected); FItemX := P.X; FItemY := P.Y; end;
end;
procedure TLaserBedCanvas.LayoutChanged;
begin Invalidate; if Assigned(FOnLayoutChanged) then FOnLayoutChanged(Self); end;
procedure TLaserBedCanvas.MouseMove(Shift: TShiftState; X,Y: Integer);
var P: TLaserLayoutItem; NX,NY: Double;
begin
  inherited;
  if not FDragging or (FLayout = nil) or (FSelected < 0) then Exit;
  P := FLayout.Item(FSelected); if P.Locked then Exit;
  NX := FItemX+(X-FStartX)/FZoom; NY := FItemY-(Y-FStartY)/FZoom;
  if FSnap > 0 then begin NX := Round(NX/FSnap)*FSnap; NY := Round(NY/FSnap)*FSnap; end;
  P.X := NX; P.Y := NY; LayoutChanged;
end;
procedure TLaserBedCanvas.MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin inherited; FDragging := False; end;
procedure TLaserBedCanvas.RotateSelected90;
var P: TLaserLayoutItem;
begin
  if (FLayout = nil) or (FSelected < 0) then Exit;
  P := FLayout.Item(FSelected); if P.Locked then Exit;
  P.Rotation := P.Rotation+90; if P.Rotation >= 360 then P.Rotation := P.Rotation-360;
  LayoutChanged;
end;
end.
