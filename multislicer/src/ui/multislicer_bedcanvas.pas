unit multislicer_bedcanvas;
{$mode objfpc}{$H+}
interface
uses Classes,Controls,Graphics,Math,multislicer_layout3d;
type TPrintBedCanvas=class(TCustomControl)
 private FLayout:TPrintBedLayout;FSelected:Integer;FZoom:Double;FDrag:Boolean;LX,LY:Integer;function Hit(X,Y:Double):Integer;
 protected procedure Paint;override;procedure MouseDown(B:TMouseButton;S:TShiftState;X,Y:Integer);override;procedure MouseMove(S:TShiftState;X,Y:Integer);override;procedure MouseUp(B:TMouseButton;S:TShiftState;X,Y:Integer);override;
 public constructor Create(AOwner:TComponent);override;procedure RotateZ90;procedure CenterSelected;procedure ZoomIn;procedure ZoomOut;property Layout:TPrintBedLayout read FLayout write FLayout;
 end;
implementation
constructor TPrintBedCanvas.Create(AOwner:TComponent);begin inherited;FSelected:=-1;FZoom:=2;Color:=clWhite;end;
function TPrintBedCanvas.Hit(X,Y:Double):Integer;var I:Integer;P:TModelPlacement;begin Result:=-1;if not Assigned(FLayout)then Exit;for I:=FLayout.Count-1 downto 0 do begin P:=FLayout.Item(I);if(X>=P.X)and(Y>=P.Y)and(X<=P.X+P.BoundX)and(Y<=P.Y+P.BoundY)then Exit(I);end;end;
procedure TPrintBedCanvas.Paint;var I,G:Integer;P:TModelPlacement;R:TRect;begin inherited;Canvas.Brush.Color:=clWhite;Canvas.FillRect(ClientRect);if not Assigned(FLayout)then Exit;Canvas.Pen.Color:=clSilver;for G:=0 to Trunc(FLayout.BedX/10)do begin Canvas.MoveTo(Round(G*10*FZoom),0);Canvas.LineTo(Round(G*10*FZoom),Round(FLayout.BedY*FZoom));end;for G:=0 to Trunc(FLayout.BedY/10)do begin Canvas.MoveTo(0,Round(G*10*FZoom));Canvas.LineTo(Round(FLayout.BedX*FZoom),Round(G*10*FZoom));end;Canvas.Pen.Color:=clBlack;Canvas.Rectangle(0,0,Round(FLayout.BedX*FZoom),Round(FLayout.BedY*FZoom));for I:=0 to FLayout.Count-1 do begin P:=FLayout.Item(I);R:=Rect(Round(P.X*FZoom),Round(P.Y*FZoom),Round((P.X+P.BoundX)*FZoom),Round((P.Y+P.BoundY)*FZoom));if I=FSelected then Canvas.Pen.Width:=3 else Canvas.Pen.Width:=1;Canvas.Rectangle(R);Canvas.TextOut(R.Left+3,R.Top+3,P.Name);end;Canvas.Pen.Width:=1;end;
procedure TPrintBedCanvas.MouseDown(B:TMouseButton;S:TShiftState;X,Y:Integer);begin inherited;if B<>mbLeft then Exit;FSelected:=Hit(X/FZoom,Y/FZoom);FDrag:=FSelected>=0;LX:=X;LY:=Y;Invalidate;end;
procedure TPrintBedCanvas.MouseMove(S:TShiftState;X,Y:Integer);var P:TModelPlacement;begin inherited;if not FDrag then Exit;P:=FLayout.Item(FSelected);if P.Locked then Exit;P.X:=P.X+(X-LX)/FZoom;P.Y:=P.Y+(Y-LY)/FZoom;LX:=X;LY:=Y;Invalidate;end;
procedure TPrintBedCanvas.MouseUp(B:TMouseButton;S:TShiftState;X,Y:Integer);begin inherited;FDrag:=False;end;
procedure TPrintBedCanvas.RotateZ90;begin if FSelected<0 then Exit;FLayout.Item(FSelected).RotZ:=FLayout.Item(FSelected).RotZ+90;Invalidate;end;
procedure TPrintBedCanvas.CenterSelected;begin if FSelected<0 then Exit;FLayout.Center(FSelected);Invalidate;end;
procedure TPrintBedCanvas.ZoomIn;begin FZoom:=Min(8,FZoom*1.25);Invalidate;end;
procedure TPrintBedCanvas.ZoomOut;begin FZoom:=Max(0.25,FZoom/1.25);Invalidate;end;
end.
