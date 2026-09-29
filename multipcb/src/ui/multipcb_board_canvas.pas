unit multipcb_board_canvas;
{$mode objfpc}{$H+}
interface
uses Classes,Controls,Graphics,Math,multipcb_types,multipcb_model,multipcb_board,multipcb_ratsnest,multipcb_router;
type TBoardTool=(btSelect,btRoute);
 TBoardCanvas=class(TCustomControl)
 private FBoard:TBoard;FRatsnest:TRatsnest;FZoom,FSnap:Double;FTool:TBoardTool;FSelected:TPCBComponent;FDragging,FRouting:Boolean;FRouteStart:TPointMM;FLayer:TPCBLayer;FNet:string;
  function ScreenToBoard(X,Y:Integer):TPointMM;function Snap(V:Double):Double;function HitComponent(const P:TPointMM):TPCBComponent;
 protected procedure Paint;override;procedure MouseDown(Button:TMouseButton;Shift:TShiftState;X,Y:Integer);override;procedure MouseMove(Shift:TShiftState;X,Y:Integer);override;procedure MouseUp(Button:TMouseButton;Shift:TShiftState;X,Y:Integer);override;
 public constructor Create(AOwner:TComponent);override;procedure SetRouteMode(const Net:string);procedure SetSelectMode;procedure ToggleLayerWithVia;property Board:TBoard read FBoard write FBoard;property Ratsnest:TRatsnest read FRatsnest write FRatsnest;property SnapMM:Double read FSnap write FSnap;procedure ZoomIn;procedure ZoomOut;
 end;
implementation
constructor TBoardCanvas.Create(AOwner:TComponent);begin inherited;FZoom:=5;FSnap:=1;FTool:=btSelect;FLayer:=plTopCopper;FNet:='N$1';Color:=clWhite;end;
function TBoardCanvas.Snap(V:Double):Double;begin if FSnap<=0 then Exit(V);Result:=Round(V/FSnap)*FSnap;end;
function TBoardCanvas.ScreenToBoard(X,Y:Integer):TPointMM;begin Result.X:=Snap((X-20)/FZoom);Result.Y:=Snap((Y-20)/FZoom);end;
function TBoardCanvas.HitComponent(const P:TPointMM):TPCBComponent;var I:Integer;C:TPCBComponent;begin Result:=nil;if not Assigned(FBoard)then Exit;for I:=FBoard.Project.Components.Count-1 downto 0 do begin C:=TPCBComponent(FBoard.Project.Components[I]);if(Abs(P.X-C.X)<=4)and(Abs(P.Y-C.Y)<=4)then Exit(C);end;end;
procedure TBoardCanvas.SetRouteMode(const Net:string);begin FTool:=btRoute;if Net<>''then FNet:=Net;FDragging:=False;FRouting:=False;end;
procedure TBoardCanvas.SetSelectMode;begin FTool:=btSelect;FRouting:=False;end;
procedure TBoardCanvas.ToggleLayerWithVia;begin if not FRouting then Exit;if FLayer=plTopCopper then FLayer:=plBottomCopper else FLayer:=plTopCopper;FBoard.AddVia(FRouteStart.X,FRouteStart.Y,1.6,.8,FNet);Invalidate;end;
procedure TBoardCanvas.MouseDown(Button:TMouseButton;Shift:TShiftState;X,Y:Integer);var P:TPointMM;begin inherited;if Button<>mbLeft then Exit;P:=ScreenToBoard(X,Y);if FTool=btSelect then begin FSelected:=HitComponent(P);FDragging:=Assigned(FSelected);end else if not FRouting then begin FRouteStart:=P;FRouting:=True;end else begin TInteractiveRouter.Route(FBoard,FRouteStart,P,.4,FLayer,FNet,rm45Degree);FRouteStart:=P;Invalidate;end;end;
procedure TBoardCanvas.MouseMove(Shift:TShiftState;X,Y:Integer);var P:TPointMM;begin inherited;if FDragging and Assigned(FSelected)then begin P:=ScreenToBoard(X,Y);FSelected.X:=P.X;FSelected.Y:=P.Y;Invalidate;end;end;
procedure TBoardCanvas.MouseUp(Button:TMouseButton;Shift:TShiftState;X,Y:Integer);begin inherited;if Button=mbLeft then FDragging:=False;end;
procedure TBoardCanvas.Paint;var I:Integer;T:TTrack;V:TVia;C:TPCBComponent;R:TRatsLine;
begin Canvas.Brush.Color:=clWhite;Canvas.FillRect(ClientRect);if not Assigned(FBoard)or not Assigned(FBoard.Project)then Exit;Canvas.Brush.Style:=bsClear;Canvas.Pen.Width:=1;Canvas.Pen.Color:=clBlack;Canvas.Rectangle(20,20,20+Round(FBoard.Project.BoardWidth*FZoom),20+Round(FBoard.Project.BoardHeight*FZoom));
if Assigned(FRatsnest)then begin Canvas.Pen.Style:=psDot;Canvas.Pen.Color:=clGray;for I:=0 to FRatsnest.Count-1 do begin R:=FRatsnest.Line(I);Canvas.MoveTo(20+Round(R.A.X*FZoom),20+Round(R.A.Y*FZoom));Canvas.LineTo(20+Round(R.B.X*FZoom),20+Round(R.B.Y*FZoom));end;Canvas.Pen.Style:=psSolid;end;
for I:=0 to FBoard.Project.Components.Count-1 do begin C:=TPCBComponent(FBoard.Project.Components[I]);if C=FSelected then Canvas.Pen.Color:=clFuchsia else Canvas.Pen.Color:=clBlack;Canvas.Rectangle(20+Round((C.X-3)*FZoom),20+Round((C.Y-3)*FZoom),20+Round((C.X+3)*FZoom),20+Round((C.Y+3)*FZoom));Canvas.TextOut(20+Round(C.X*FZoom),20+Round(C.Y*FZoom),C.Ref);end;
for I:=0 to FBoard.TrackCount-1 do begin T:=FBoard.TrackAt(I);if T.Layer=plTopCopper then Canvas.Pen.Color:=clRed else Canvas.Pen.Color:=clBlue;Canvas.Pen.Width:=Max(1,Round(T.Width*FZoom));Canvas.MoveTo(20+Round(T.A.X*FZoom),20+Round(T.A.Y*FZoom));Canvas.LineTo(20+Round(T.B.X*FZoom),20+Round(T.B.Y*FZoom));end;Canvas.Pen.Width:=1;
for I:=0 to FBoard.ViaCount-1 do begin V:=FBoard.ViaAt(I);Canvas.Pen.Color:=clBlack;Canvas.Ellipse(20+Round((V.Position.X-V.Diameter/2)*FZoom),20+Round((V.Position.Y-V.Diameter/2)*FZoom),20+Round((V.Position.X+V.Diameter/2)*FZoom),20+Round((V.Position.Y+V.Diameter/2)*FZoom));end;end;
procedure TBoardCanvas.ZoomIn;begin FZoom:=Min(30,FZoom*1.25);Invalidate;end;procedure TBoardCanvas.ZoomOut;begin FZoom:=Max(.25,FZoom/1.25);Invalidate;end;
end.
