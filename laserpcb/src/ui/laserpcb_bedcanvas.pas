unit laserpcb_bedcanvas;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Math,Controls,Graphics,LCLType,laserpcb_layout;
type
 TLaserBedCanvas=class(TCustomControl)
 private FLayout:TLaserBedLayout;FSelected:Integer;FZoom,FSnap:Double;FDragging:Boolean;FLastX,FLastY:Integer;
  procedure SetLayout(AValue:TLaserBedLayout);function MMX(PX:Integer):Double;function MMY(PY:Integer):Double;function HitTest(X,Y:Double):Integer;
 protected procedure Paint;override;procedure MouseDown(Button:TMouseButton;Shift:TShiftState;X,Y:Integer);override;procedure MouseMove(Shift:TShiftState;X,Y:Integer);override;procedure MouseUp(Button:TMouseButton;Shift:TShiftState;X,Y:Integer);override;
 public constructor Create(AOwner:TComponent);override;procedure RotateSelected90;procedure ZoomIn;procedure ZoomOut;property Layout:TLaserBedLayout read FLayout write SetLayout;property SelectedIndex:Integer read FSelected;property SnapMM:Double read FSnap write FSnap;
 end;
implementation
constructor TLaserBedCanvas.Create(AOwner:TComponent);begin inherited;FSelected:=-1;FZoom:=1;FSnap:=1;Color:=clWhite;end;
procedure TLaserBedCanvas.SetLayout(AValue:TLaserBedLayout);begin FLayout:=AValue;Invalidate;end;
function TLaserBedCanvas.MMX(PX:Integer):Double;begin Result:=PX/FZoom;end;
function TLaserBedCanvas.MMY(PY:Integer):Double;begin Result:=PY/FZoom;end;
function TLaserBedCanvas.HitTest(X,Y:Double):Integer;var I:Integer;P:TLaserLayoutItem;begin Result:=-1;if not Assigned(FLayout)then Exit;for I:=FLayout.Count-1 downto 0 do begin P:=FLayout.Item(I);if(X>=P.X)and(Y>=P.Y)and(X<=P.X+P.PlacedWidth)and(Y<=P.Y+P.PlacedHeight)then Exit(I);end;end;
procedure TLaserBedCanvas.Paint;var I:Integer;P:TLaserLayoutItem;R:TRect;begin inherited;Canvas.Brush.Color:=clWhite;Canvas.FillRect(ClientRect);if not Assigned(FLayout)then Exit;Canvas.Pen.Color:=clBlack;Canvas.Brush.Style:=bsClear;Canvas.Rectangle(0,0,Round(FLayout.BedWidth*FZoom),Round(FLayout.BedHeight*FZoom));for I:=0 to FLayout.Count-1 do begin P:=FLayout.Item(I);R:=Rect(Round(P.X*FZoom),Round(P.Y*FZoom),Round((P.X+P.PlacedWidth)*FZoom),Round((P.Y+P.PlacedHeight)*FZoom));if I=FSelected then Canvas.Pen.Width:=3 else Canvas.Pen.Width:=1;Canvas.Rectangle(R);Canvas.TextOut(R.Left+3,R.Top+3,P.Name);end;Canvas.Pen.Width:=1;end;
procedure TLaserBedCanvas.MouseDown(Button:TMouseButton;Shift:TShiftState;X,Y:Integer);begin inherited;if Button<>mbLeft then Exit;FSelected:=HitTest(MMX(X),MMY(Y));FDragging:=FSelected>=0;FLastX:=X;FLastY:=Y;Invalidate;end;
procedure TLaserBedCanvas.MouseMove(Shift:TShiftState;X,Y:Integer);var P:TLaserLayoutItem;DX,DY:Double;begin inherited;if not FDragging then Exit;P:=FLayout.Item(FSelected);if P.Locked then Exit;DX:=(X-FLastX)/FZoom;DY:=(Y-FLastY)/FZoom;P.X:=Round((P.X+DX)/FSnap)*FSnap;P.Y:=Round((P.Y+DY)/FSnap)*FSnap;FLastX:=X;FLastY:=Y;Invalidate;end;
procedure TLaserBedCanvas.MouseUp(Button:TMouseButton;Shift:TShiftState;X,Y:Integer);begin inherited;FDragging:=False;end;
procedure TLaserBedCanvas.RotateSelected90;var P:TLaserLayoutItem;begin if(FSelected<0)or not Assigned(FLayout)then Exit;P:=FLayout.Item(FSelected);if P.Locked then Exit;P.Rotation:=P.Rotation+90;if P.Rotation>=360 then P.Rotation:=P.Rotation-360;Invalidate;end;
procedure TLaserBedCanvas.ZoomIn;begin FZoom:=Min(5,FZoom*1.25);Invalidate;end;
procedure TLaserBedCanvas.ZoomOut;begin FZoom:=Max(0.1,FZoom/1.25);Invalidate;end;
end.
