unit multipcb_cnc_canvas;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Math,Controls,Graphics,multipcb_cnc_position,multipcb_cnc_fixture,multipcb_probeplan;
type
 TPCBCNCCanvas=class(TCustomControl)
 private FPlacement:TPCBPlacement;FProbePlan:TProbePlan;FZoom:Double;FShowProbe:Boolean;
 public constructor Create(AOwner:TComponent);override;procedure Paint;override;procedure ZoomIn;procedure ZoomOut;
  property Placement:TPCBPlacement read FPlacement write FPlacement;property ProbePlan:TProbePlan read FProbePlan write FProbePlan;property ShowProbe:Boolean read FShowProbe write FShowProbe;
 end;
implementation
constructor TPCBCNCCanvas.Create(AOwner:TComponent);begin inherited;FZoom:=2;Color:=clWhite;end;
procedure TPCBCNCCanvas.Paint;
var A,B,C,D:TPCBPoint;R:TRect;I:Integer;T:TProbeTarget;FaceText:string;
begin inherited;Canvas.Brush.Color:=clWhite;Canvas.FillRect(ClientRect);if not Assigned(FPlacement)then Exit;
 A.X:=0;A.Y:=0;B.X:=FPlacement.BoardWidth;B.Y:=0;C.X:=FPlacement.BoardWidth;C.Y:=FPlacement.BoardHeight;D.X:=0;D.Y:=FPlacement.BoardHeight;
 A:=FPlacement.Transform(A);B:=FPlacement.Transform(B);C:=FPlacement.Transform(C);D:=FPlacement.Transform(D);
 Canvas.Pen.Color:=clBlack;Canvas.Brush.Style:=bsClear;Canvas.MoveTo(Round(A.X*FZoom),Round(A.Y*FZoom));Canvas.LineTo(Round(B.X*FZoom),Round(B.Y*FZoom));Canvas.LineTo(Round(C.X*FZoom),Round(C.Y*FZoom));Canvas.LineTo(Round(D.X*FZoom),Round(D.Y*FZoom));Canvas.LineTo(Round(A.X*FZoom),Round(A.Y*FZoom));
 Canvas.Ellipse(Round((FPlacement.OriginX-1)*FZoom),Round((FPlacement.OriginY-1)*FZoom),Round((FPlacement.OriginX+1)*FZoom),Round((FPlacement.OriginY+1)*FZoom));
 if FPlacement.Face=pfTop then FaceText:='TOP' else FaceText:='BOTTOM';Canvas.TextOut(Round(A.X*FZoom)+5,Round(A.Y*FZoom)+5,FaceText);
 if FShowProbe and Assigned(FProbePlan)then for I:=0 to FProbePlan.Count-1 do begin T:=FProbePlan.Target(I);R:=Rect(Round(T.X*FZoom)-2,Round(T.Y*FZoom)-2,Round(T.X*FZoom)+3,Round(T.Y*FZoom)+3);Canvas.Ellipse(R);end;
end;
procedure TPCBCNCCanvas.ZoomIn;begin FZoom:=Min(10,FZoom*1.25);Invalidate;end;
procedure TPCBCNCCanvas.ZoomOut;begin FZoom:=Max(0.2,FZoom/1.25);Invalidate;end;
end.
