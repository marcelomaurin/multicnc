unit multicad_viewport;
{$mode objfpc}{$H+}
interface
uses Classes,Controls,Graphics,Math,multicad_document,multicad_feature,multicad_sketch;
type TCadViewport=class(TCustomControl)
 private FDocument:TCadDocument;FZoom:Double;FOffsetX,FOffsetY:Double;procedure DrawSketch(S:TCadSketch);
 protected procedure Paint;override;
 public constructor Create(AOwner:TComponent);override;procedure Fit;procedure ZoomIn;procedure ZoomOut;property Document:TCadDocument read FDocument write FDocument;
 end;
implementation
constructor TCadViewport.Create(AOwner:TComponent);begin inherited;Color:=clWhite;FZoom:=4;FOffsetX:=Width/2;FOffsetY:=Height/2;end;
procedure TCadViewport.DrawSketch(S:TCadSketch);var I:Integer;E:TSketchEntity;X1,Y1,X2,Y2,R:Integer;begin Canvas.Pen.Color:=clBlack;for I:=0 to S.EntityCount-1 do begin E:=S.Entity(I);X1:=Round(FOffsetX+E.P1.X*FZoom);Y1:=Round(FOffsetY-E.P1.Y*FZoom);case E.Kind of seLine:begin X2:=Round(FOffsetX+E.P2.X*FZoom);Y2:=Round(FOffsetY-E.P2.Y*FZoom);Canvas.MoveTo(X1,Y1);Canvas.LineTo(X2,Y2);end;seCircle:begin R:=Round(E.Radius*FZoom);Canvas.Ellipse(X1-R,Y1-R,X1+R,Y1+R);end;end;end;end;
procedure TCadViewport.Paint;var I:Integer;begin inherited;Canvas.Brush.Color:=clWhite;Canvas.FillRect(ClientRect);FOffsetX:=Width/2;FOffsetY:=Height/2;Canvas.Pen.Color:=clSilver;Canvas.MoveTo(0,Round(FOffsetY));Canvas.LineTo(Width,Round(FOffsetY));Canvas.MoveTo(Round(FOffsetX),0);Canvas.LineTo(Round(FOffsetX),Height);if not Assigned(FDocument)then Exit;for I:=0 to FDocument.Count-1 do if FDocument.Feature(I) is TCadSketch then DrawSketch(TCadSketch(FDocument.Feature(I)));end;
procedure TCadViewport.Fit;begin FZoom:=4;Invalidate;end;procedure TCadViewport.ZoomIn;begin FZoom:=Min(50,FZoom*1.25);Invalidate;end;procedure TCadViewport.ZoomOut;begin FZoom:=Max(.1,FZoom/1.25);Invalidate;end;
end.
