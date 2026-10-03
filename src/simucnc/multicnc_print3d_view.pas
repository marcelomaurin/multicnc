unit multicnc_print3d_view;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Controls, Graphics, Math, aimarlinsimulator;
type
  TPrintSegment = record A, B: TAIMarlinPosition; Material: Double; end;
  TPrint3DView = class(TCustomControl)
  private FSegments: array of TPrintSegment; FCurrent: TAIMarlinPosition; FRotX,FRotZ,FZoom:Double; FDrag:Boolean; FLastX,FLastY:Integer; procedure Project(const P:TAIMarlinPosition; out Q:TPoint);
  protected procedure Paint; override; procedure MouseDown(Button:TMouseButton;Shift:TShiftState;X,Y:Integer); override; procedure MouseMove(Shift:TShiftState;X,Y:Integer); override; procedure MouseUp(Button:TMouseButton;Shift:TShiftState;X,Y:Integer); override; function DoMouseWheel(Shift:TShiftState;WheelDelta:Integer;MousePos:TPoint):Boolean; override;
  public constructor Create(AOwner:TComponent); override; procedure ClearPrint; procedure AddMotion(Sender:TObject;const A,B:TAIMarlinPosition;Material:Double); procedure SetPosition(const P:TAIMarlinPosition); procedure ResetView;
  end;
implementation
constructor TPrint3DView.Create(AOwner:TComponent); begin inherited Create(AOwner); Color:=clWhite; FRotX:=58; FRotZ:=-38; FZoom:=1.4; DoubleBuffered:=True; end;
procedure TPrint3DView.ClearPrint; begin SetLength(FSegments,0); FillChar(FCurrent,SizeOf(FCurrent),0); Invalidate; end;
procedure TPrint3DView.AddMotion(Sender:TObject;const A,B:TAIMarlinPosition;Material:Double); var N:Integer; begin FCurrent:=B; if Material>0 then begin N:=Length(FSegments); SetLength(FSegments,N+1); FSegments[N].A:=A; FSegments[N].B:=B; FSegments[N].Material:=Material; end; Invalidate; end;
procedure TPrint3DView.SetPosition(const P:TAIMarlinPosition); begin FCurrent:=P; Invalidate; end;
procedure TPrint3DView.ResetView; begin FRotX:=58; FRotZ:=-38; FZoom:=1.4; Invalidate; end;
procedure TPrint3DView.Project(const P:TAIMarlinPosition;out Q:TPoint); var X,Y,Z,RX,RZ,CX,SX,CZ,SZ,S:Double; begin X:=P.X-110;Y:=P.Y-110;Z:=P.Z;RZ:=FRotZ*Pi/180;RX:=FRotX*Pi/180;CZ:=Cos(RZ);SZ:=Sin(RZ);CX:=Cos(RX);SX:=Sin(RX);S:=Min(ClientWidth,ClientHeight)*0.0028*FZoom;Q.X:=ClientWidth div 2+Round((X*CZ-Y*SZ)*S);Q.Y:=ClientHeight div 2+Round(((X*SZ+Y*CZ)*CX-Z*SX)*S); end;
procedure TPrint3DView.Paint; var Q1,Q2:TPoint;I,G:Integer;P:TAIMarlinPosition;R:TRect; begin inherited;Canvas.Brush.Color:=RGBToColor(245,247,250);Canvas.FillRect(ClientRect);R:=Rect(80,ClientHeight-100,ClientWidth-60,ClientHeight-55);Canvas.Brush.Color:=RGBToColor(225,230,236);Canvas.Pen.Color:=RGBToColor(170,180,190);Canvas.Rectangle(R);for G:=0 to 11 do begin Canvas.Pen.Color:=RGBToColor(210,215,220);Canvas.MoveTo(R.Left+G*(R.Width div 11),R.Top);Canvas.LineTo(R.Left+G*(R.Width div 11),R.Bottom);Canvas.MoveTo(R.Left,R.Top+G*(R.Height div 11));Canvas.LineTo(R.Right,R.Top+G*(R.Height div 11));end;Canvas.Font.Color:=clGrayText;Canvas.TextOut(12,12,'Simulador 3D Marlin - arraste para girar, roda para zoom');for I:=0 to High(FSegments) do begin Project(FSegments[I].A,Q1);Project(FSegments[I].B,Q2);Canvas.Pen.Width:=Max(1,Round(2+FSegments[I].Material*0.4));Canvas.Pen.Color:=RGBToColor(220,80,45);Canvas.Line(Q1,Q2);end;Canvas.Pen.Width:=1;P:=FCurrent;Project(P,Q1);Canvas.Brush.Color:=clRed;Canvas.Pen.Color:=clMaroon;Canvas.Ellipse(Q1.X-5,Q1.Y-5,Q1.X+5,Q1.Y+5);Canvas.TextOut(Q1.X+8,Q1.Y-8,Format('Bico X%.2f Y%.2f Z%.2f',[P.X,P.Y,P.Z]));end;
procedure TPrint3DView.MouseDown(Button:TMouseButton;Shift:TShiftState;X,Y:Integer);begin if Button=mbLeft then begin FDrag:=True;FLastX:=X;FLastY:=Y;end;end;
procedure TPrint3DView.MouseMove(Shift:TShiftState;X,Y:Integer);begin if FDrag then begin FRotZ:=FRotZ+(X-FLastX);FRotX:=EnsureRange(FRotX+(Y-FLastY),15,85);FLastX:=X;FLastY:=Y;Invalidate;end;end;
procedure TPrint3DView.MouseUp(Button:TMouseButton;Shift:TShiftState;X,Y:Integer);begin FDrag:=False;end;
function TPrint3DView.DoMouseWheel(Shift:TShiftState;WheelDelta:Integer;MousePos:TPoint):Boolean;begin Result:=True;if WheelDelta>0 then FZoom:=Min(8,FZoom*1.12)else FZoom:=Max(0.3,FZoom/1.12);Invalidate;end;
end.
