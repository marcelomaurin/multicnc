unit multipcb_board_canvas;
{$mode objfpc}{$H+}
interface
uses Classes,Controls,Graphics,Math,multipcb_types,multipcb_model,multipcb_board,multipcb_ratsnest;
type TBoardCanvas=class(TCustomControl)
 private FBoard:TBoard;FRatsnest:TRatsnest;FZoom:Double;
 protected procedure Paint;override;
 public constructor Create(AOwner:TComponent);override;property Board:TBoard read FBoard write FBoard;property Ratsnest:TRatsnest read FRatsnest write FRatsnest;procedure ZoomIn;procedure ZoomOut;
 end;
implementation
constructor TBoardCanvas.Create(AOwner:TComponent);begin inherited;FZoom:=5;Color:=clWhite;end;
procedure TBoardCanvas.Paint;var I:Integer;T:TTrack;V:TVia;C:TPCBComponent;R:TRatsLine;
begin Canvas.Brush.Color:=clWhite;Canvas.FillRect(ClientRect);if not Assigned(FBoard)or not Assigned(FBoard.Project)then Exit;Canvas.Brush.Style:=bsClear;Canvas.Pen.Width:=1;Canvas.Pen.Color:=clBlack;Canvas.Rectangle(20,20,20+Round(FBoard.Project.BoardWidth*FZoom),20+Round(FBoard.Project.BoardHeight*FZoom));
if Assigned(FRatsnest)then begin Canvas.Pen.Style:=psDot;Canvas.Pen.Color:=clGray;for I:=0 to FRatsnest.Count-1 do begin R:=FRatsnest.Line(I);Canvas.MoveTo(20+Round(R.A.X*FZoom),20+Round(R.A.Y*FZoom));Canvas.LineTo(20+Round(R.B.X*FZoom),20+Round(R.B.Y*FZoom));end;Canvas.Pen.Style:=psSolid;end;
for I:=0 to FBoard.Project.Components.Count-1 do begin C:=TPCBComponent(FBoard.Project.Components[I]);Canvas.Pen.Color:=clBlack;Canvas.Rectangle(20+Round((C.X-3)*FZoom),20+Round((C.Y-3)*FZoom),20+Round((C.X+3)*FZoom),20+Round((C.Y+3)*FZoom));Canvas.TextOut(20+Round(C.X*FZoom),20+Round(C.Y*FZoom),C.Ref);end;
for I:=0 to FBoard.TrackCount-1 do begin T:=FBoard.TrackAt(I);if T.Layer=plTopCopper then Canvas.Pen.Color:=clRed else Canvas.Pen.Color:=clBlue;Canvas.Pen.Width:=Max(1,Round(T.Width*FZoom));Canvas.MoveTo(20+Round(T.A.X*FZoom),20+Round(T.A.Y*FZoom));Canvas.LineTo(20+Round(T.B.X*FZoom),20+Round(T.B.Y*FZoom));end;Canvas.Pen.Width:=1;
for I:=0 to FBoard.ViaCount-1 do begin V:=FBoard.ViaAt(I);Canvas.Pen.Color:=clBlack;Canvas.Ellipse(20+Round((V.Position.X-V.Diameter/2)*FZoom),20+Round((V.Position.Y-V.Diameter/2)*FZoom),20+Round((V.Position.X+V.Diameter/2)*FZoom),20+Round((V.Position.Y+V.Diameter/2)*FZoom));end;end;
procedure TBoardCanvas.ZoomIn;begin FZoom:=Min(30,FZoom*1.25);Invalidate;end;procedure TBoardCanvas.ZoomOut;begin FZoom:=Max(.25,FZoom/1.25);Invalidate;end;
end.
