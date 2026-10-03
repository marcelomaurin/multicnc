unit multicnc_print3d_view;
{$mode objfpc}{$H+}
interface
uses multisuite_numfmt, Classes, SysUtils, Controls, Graphics, Math, aimarlinsimulator;
type
  TPrintSegment = record A, B: TAIMarlinPosition; Material: Double; end;
  TPrint3DView = class(TCustomControl)
  private FShowFrame:Boolean; procedure SetShowFrame(Value:Boolean); function GetSegmentCount:Integer;
  private FSegments: array of TPrintSegment; FCurrent: TAIMarlinPosition; FLaserMode:Boolean; FVolumeX,FVolumeY,FVolumeZ:Double; FRotX,FRotZ,FZoom:Double; FDrag:Boolean; FLastX,FLastY:Integer; procedure Project(const P:TAIMarlinPosition; out Q:TPoint);
  protected procedure Paint; override; procedure DblClick; override; procedure MouseDown(Button:TMouseButton;Shift:TShiftState;X,Y:Integer); override; procedure MouseMove(Shift:TShiftState;X,Y:Integer); override; procedure MouseUp(Button:TMouseButton;Shift:TShiftState;X,Y:Integer); override; function DoMouseWheel(Shift:TShiftState;WheelDelta:Integer;MousePos:TPoint):Boolean; override;
  public procedure RenderScene(ACanvas:TCanvas);
    constructor Create(AOwner:TComponent); override; procedure ClearPrint; procedure AddMotion(Sender:TObject;const A,B:TAIMarlinPosition;Material:Double); procedure SetPosition(const P:TAIMarlinPosition); procedure ResetView; procedure TopView; procedure FrontView;
    procedure AddLaserMotion(const A,B:TAIMarlinPosition; Power:Double);
    procedure SetBuildVolume(X,Y,Z:Double);
    property ShowFrame:Boolean read FShowFrame write SetShowFrame;
    property LaserMode:Boolean read FLaserMode write FLaserMode;
    property VolumeX:Double read FVolumeX;
    property VolumeY:Double read FVolumeY;
    property VolumeZ:Double read FVolumeZ;
    property SegmentCount:Integer read GetSegmentCount;
    { Trecho I desenhado; Material<0 indica queima de laser (-potencia). }
    function Segment(I:Integer):TPrintSegment;
    property CurrentPosition:TAIMarlinPosition read FCurrent;
  end;
implementation
constructor TPrint3DView.Create(AOwner:TComponent); begin inherited Create(AOwner); Color:=clWhite; FVolumeX:=220;FVolumeY:=220;FVolumeZ:=250; FRotX:=58; FRotZ:=-38; FZoom:=1.0; DoubleBuffered:=True; end;
procedure TPrint3DView.SetBuildVolume(X,Y,Z:Double); begin if (X>0) and (Y>0) and (Z>0) then begin FVolumeX:=X;FVolumeY:=Y;FVolumeZ:=Z;Invalidate;end;end;
function TPrint3DView.GetSegmentCount:Integer;begin Result:=Length(FSegments);end;
function TPrint3DView.Segment(I:Integer):TPrintSegment;begin Result:=FSegments[I];end;
procedure TPrint3DView.ClearPrint; begin SetLength(FSegments,0); FillChar(FCurrent,SizeOf(FCurrent),0); Invalidate; end;
procedure TPrint3DView.AddMotion(Sender:TObject;const A,B:TAIMarlinPosition;Material:Double); var N:Integer; begin FCurrent:=B; if Material>0 then begin N:=Length(FSegments); SetLength(FSegments,N+1); FSegments[N].A:=A; FSegments[N].B:=B; FSegments[N].Material:=Material; end; Invalidate; end;
procedure TPrint3DView.AddLaserMotion(const A,B:TAIMarlinPosition; Power:Double); var N:Integer; begin FCurrent:=B; if Power>0 then begin N:=Length(FSegments); SetLength(FSegments,N+1); FSegments[N].A:=A; FSegments[N].B:=B; FSegments[N].Material:=-Power; end; Invalidate; end;
procedure TPrint3DView.SetPosition(const P:TAIMarlinPosition); begin FCurrent:=P; Invalidate; end;
procedure TPrint3DView.ResetView; begin FRotX:=58; FRotZ:=-38; FZoom:=1.0; Invalidate; end;
procedure TPrint3DView.SetShowFrame(Value:Boolean);
begin FShowFrame:=Value;Invalidate;end;
procedure TPrint3DView.TopView;
begin FRotX:=0;FRotZ:=0;Invalidate;end;
procedure TPrint3DView.FrontView;
begin FRotX:=85;FRotZ:=0;Invalidate;end;
procedure TPrint3DView.Project(const P:TAIMarlinPosition;out Q:TPoint); var X,Y,Z,RX,RZ,CX,SX,CZ,SZ,S:Double; begin X:=P.X-FVolumeX/2;Y:=P.Y-FVolumeY/2;Z:=P.Z;RZ:=FRotZ*Pi/180;RX:=FRotX*Pi/180;CZ:=Cos(RZ);SZ:=Sin(RZ);CX:=Cos(RX);SX:=Sin(RX);S:=Min(ClientWidth,ClientHeight)/Max(Max(FVolumeX,FVolumeY),FVolumeZ*0.8);if FShowFrame then S:=S*0.55*FZoom else S:=S*0.78*FZoom;Q.X:=ClientWidth div 2+Round((X*CZ-Y*SZ)*S);if FShowFrame then Q.Y:=Round(ClientHeight*0.67) else Q.Y:=Round(ClientHeight*0.53);Q.Y:=Q.Y+Round(((X*SZ+Y*CZ)*CX-Z*SX)*S); end;
procedure TPrint3DView.Paint;
begin inherited;RenderScene(Canvas);end;
procedure TPrint3DView.RenderScene(ACanvas:TCanvas);
var I,G: Integer; Q:TPoint; X,Y,Z:Double;
  function Pos3(AX,AY,AZ:Double):TAIMarlinPosition;
  begin FillChar(Result,SizeOf(Result),0); Result.X:=AX;Result.Y:=AY;Result.Z:=AZ;end;
  procedure Line3(X1,Y1,Z1,X2,Y2,Z2:Double; C:TColor; W:Integer);
  var A,B:TPoint;
  begin
    Project(Pos3(X1,Y1,Z1),A);Project(Pos3(X2,Y2,Z2),B);
    ACanvas.Pen.Color:=C;ACanvas.Pen.Width:=W;ACanvas.Line(A,B);
  end;
  procedure Face(const A,B,C,D:TAIMarlinPosition; Col:TColor);
  var Points:array[0..3] of TPoint;
  begin
    Project(A,Points[0]);Project(B,Points[1]);Project(C,Points[2]);Project(D,Points[3]);
    ACanvas.Pen.Width:=1;ACanvas.Pen.Color:=Col;ACanvas.Brush.Color:=Col;
    ACanvas.Polygon(Points);
  end;
  function Shade(C:TColor; Factor:Double):TColor;
  var RGB:LongInt;
  begin RGB:=ColorToRGB(C);Result:=RGBToColor(Round((RGB and 255)*Factor),Round(((RGB shr 8) and 255)*Factor),Round(((RGB shr 16) and 255)*Factor));end;
  procedure Box3(X1,Y1,Z1,X2,Y2,Z2:Double; Col:TColor);
  begin
    Face(Pos3(X1,Y1,Z1),Pos3(X2,Y1,Z1),Pos3(X2,Y1,Z2),Pos3(X1,Y1,Z2),Shade(Col,0.7));
    Face(Pos3(X2,Y2,Z1),Pos3(X1,Y2,Z1),Pos3(X1,Y2,Z2),Pos3(X2,Y2,Z2),Shade(Col,0.7));
    Face(Pos3(X1,Y2,Z1),Pos3(X1,Y1,Z1),Pos3(X1,Y1,Z2),Pos3(X1,Y2,Z2),Shade(Col,0.8));
    Face(Pos3(X2,Y1,Z1),Pos3(X2,Y2,Z1),Pos3(X2,Y2,Z2),Pos3(X2,Y1,Z2),Shade(Col,0.8));
    Face(Pos3(X1,Y1,Z2),Pos3(X2,Y1,Z2),Pos3(X2,Y2,Z2),Pos3(X1,Y2,Z2),Col);
  end;
begin
  ACanvas.Brush.Color:=RGBToColor(17,18,21);ACanvas.FillRect(ClientRect);
  { Every part uses the same world coordinates and camera as the toolpath. }
  Box3(-16,-16,-14,236,236,-5,RGBToColor(58,69,84));
  if FLaserMode then Box3(0,0,-5,FVolumeX,FVolumeY,0,RGBToColor(255,255,255))
  else Box3(0,0,-5,FVolumeX,FVolumeY,0,RGBToColor(66,68,72));
  for G:=0 to 11 do begin
    if FLaserMode then begin
      Line3(G*FVolumeX/11,0,0,G*FVolumeX/11,FVolumeY,0,RGBToColor(205,205,205),1);
      Line3(0,G*FVolumeY/11,0,FVolumeX,G*FVolumeY/11,0,RGBToColor(205,205,205),1);
    end else begin
      Line3(G*FVolumeX/11,0,0,G*FVolumeX/11,FVolumeY,0,RGBToColor(93,96,101),1);
      Line3(0,G*FVolumeY/11,0,FVolumeX,G*FVolumeY/11,0,RGBToColor(93,96,101),1);
    end;
  end;
  { Open printer frame and moving gantry leave the work area visible. }
  X:=FCurrent.X;Y:=FCurrent.Y;Z:=FCurrent.Z;
  if FShowFrame then begin
  Line3(-12,FVolumeY+10,0,-12,FVolumeY+10,FVolumeZ,RGBToColor(139,154,174),5);
  Line3(FVolumeX+12,FVolumeY+10,0,FVolumeX+12,FVolumeY+10,FVolumeZ,RGBToColor(139,154,174),5);
  Line3(-12,FVolumeY+10,FVolumeZ,FVolumeX+12,FVolumeY+10,FVolumeZ,RGBToColor(139,154,174),5);
  X:=FCurrent.X;Y:=FCurrent.Y;Z:=FCurrent.Z;
  Line3(-12,FVolumeY+10,Z+32,FVolumeX+12,FVolumeY+10,Z+32,RGBToColor(97,118,145),4);
  Line3(X,FVolumeY+10,Z+32,X,Y,Z+32,RGBToColor(97,118,145),3);
  end;
  for I:=0 to High(FSegments) do
    with FSegments[I] do
      if Material<0 then Line3(A.X,A.Y,0.5,B.X,B.Y,0.5,RGBToColor(0,0,0),1)
      else Line3(A.X,A.Y,A.Z,B.X,B.Y,B.Z,RGBToColor(0,140+(Round(B.Z*5) mod 2)*22,220+(Round(B.Z*5) mod 2)*20),Max(2,Round(FZoom*2)));
  { Toolhead, heater block and tapered nozzle; tip is exactly at XYZ. }
  if FLaserMode then begin
    Box3(X-7,Y-7,Z+12,X+7,Y+7,Z+30,RGBToColor(210,72,52));
    Box3(X-5,Y-5,Z+6,X+5,Y+5,Z+12,RGBToColor(70,70,70));
  end else begin
    Box3(X-7,Y-7,Z+12,X+7,Y+7,Z+30,RGBToColor(59,158,209));
    Box3(X-5,Y-5,Z+6,X+5,Y+5,Z+12,RGBToColor(215,179,89));
  end;
  Face(Pos3(X-4,Y-4,Z+6),Pos3(X+4,Y-4,Z+6),Pos3(X,Y,Z),Pos3(X,Y,Z),RGBToColor(255,216,130));
  Face(Pos3(X+4,Y+4,Z+6),Pos3(X-4,Y+4,Z+6),Pos3(X,Y,Z),Pos3(X,Y,Z),RGBToColor(235,186,85));
  Face(Pos3(X-4,Y+4,Z+6),Pos3(X-4,Y-4,Z+6),Pos3(X,Y,Z),Pos3(X,Y,Z),RGBToColor(245,201,99));
  Face(Pos3(X+4,Y-4,Z+6),Pos3(X+4,Y+4,Z+6),Pos3(X,Y,Z),Pos3(X,Y,Z),RGBToColor(255,222,144));
  Project(FCurrent,Q);ACanvas.Brush.Color:=clYellow;ACanvas.Pen.Color:=clYellow;
  ACanvas.Ellipse(Q.X-3,Q.Y-3,Q.X+4,Q.Y+4);
  Line3(0,0,0,40,0,0,RGBToColor(255,92,92),2);
  Line3(0,0,0,0,40,0,RGBToColor(104,219,152),2);
  Line3(0,0,0,0,0,40,RGBToColor(97,180,255),2);
  ACanvas.Brush.Style:=bsClear;ACanvas.Font.Color:=clWhite;
  Project(Pos3(45,0,0),Q);ACanvas.TextOut(Q.X,Q.Y,'X');
  Project(Pos3(0,45,0),Q);ACanvas.TextOut(Q.X,Q.Y,'Y');
  Project(Pos3(0,0,45),Q);ACanvas.TextOut(Q.X,Q.Y,'Z');
  ACanvas.Font.Size:=12; if FLaserMode then ACanvas.TextOut(16,14,'CNC Laser | GRBL') else ACanvas.TextOut(16,14,'Impressora 3D | Marlin');
  ACanvas.Font.Size:=10;
  ACanvas.TextOut(16,40,Format('Bico  X: %.2f   Y: %.2f   Z: %.2f mm',[X,Y,Z],InvariantFS));
  ACanvas.Font.Color:=RGBToColor(181,195,213);
  ACanvas.TextOut(16,ClientHeight-40,'Arraste para girar | Roda para zoom | Duplo clique: restaurar vista');
  if FLaserMode then ACanvas.TextOut(16,ClientHeight-22,'Mesa branca | Preto: área queimada pelo laser')
  else ACanvas.TextOut(16,ClientHeight-22,Format('Mesa %.0f x %.0f mm | Altura %.0f mm | Azul: material depositado',[FVolumeX,FVolumeY,FVolumeZ],InvariantFS));
  ACanvas.Brush.Style:=bsSolid;ACanvas.Pen.Width:=1;
end;
procedure TPrint3DView.DblClick; begin inherited; ResetView; end;
procedure TPrint3DView.MouseDown(Button:TMouseButton;Shift:TShiftState;X,Y:Integer);begin if Button=mbLeft then begin FDrag:=True;MouseCapture:=True;FLastX:=X;FLastY:=Y;end;end;
procedure TPrint3DView.MouseMove(Shift:TShiftState;X,Y:Integer);begin if FDrag then begin FRotZ:=FRotZ+(X-FLastX);FRotX:=EnsureRange(FRotX+(Y-FLastY),0,85);FLastX:=X;FLastY:=Y;Invalidate;end;end;
procedure TPrint3DView.MouseUp(Button:TMouseButton;Shift:TShiftState;X,Y:Integer);begin FDrag:=False;MouseCapture:=False;end;
function TPrint3DView.DoMouseWheel(Shift:TShiftState;WheelDelta:Integer;MousePos:TPoint):Boolean;begin Result:=True;if WheelDelta>0 then FZoom:=Min(8,FZoom*1.12)else FZoom:=Max(0.3,FZoom/1.12);Invalidate;end;
end.
