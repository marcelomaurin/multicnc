unit multipcb_schematic_canvas;
{$mode objfpc}{$H+}
interface
uses Classes,Controls,Graphics,Math,multipcb_schematic;
type TSchematicCanvas=class(TCustomControl)
 private FSchematic:TSchematic;FZoom:Double;
 protected procedure Paint;override;
 public constructor Create(AOwner:TComponent);override;property Schematic:TSchematic read FSchematic write FSchematic;procedure ZoomIn;procedure ZoomOut;
 end;
implementation
constructor TSchematicCanvas.Create(AOwner:TComponent);begin inherited;FZoom:=4;Color:=clWhite;end;
procedure TSchematicCanvas.Paint;var I:Integer;S:TSchematicSymbol;W:TWire;OX,OY:Integer;begin Canvas.Brush.Color:=clWhite;Canvas.FillRect(ClientRect);OX:=Width div 2;OY:=Height div 2;Canvas.Pen.Color:=clSilver;for I:=0 to Width div 40 do begin Canvas.MoveTo(I*40,0);Canvas.LineTo(I*40,Height);end;for I:=0 to Height div 40 do begin Canvas.MoveTo(0,I*40);Canvas.LineTo(Width,I*40);end;if not Assigned(FSchematic)then Exit;Canvas.Pen.Color:=clGreen;for I:=0 to FSchematic.WireCount-1 do begin W:=FSchematic.WireAt(I);Canvas.MoveTo(OX+Round(W.A.X*FZoom),OY-Round(W.A.Y*FZoom));Canvas.LineTo(OX+Round(W.B.X*FZoom),OY-Round(W.B.Y*FZoom));end;for I:=0 to FSchematic.SymbolCount-1 do begin S:=FSchematic.SymbolAt(I);Canvas.Pen.Color:=clBlack;Canvas.Brush.Style:=bsClear;Canvas.Rectangle(OX+Round((S.Position.X-5)*FZoom),OY-Round((S.Position.Y+4)*FZoom),OX+Round((S.Position.X+5)*FZoom),OY-Round((S.Position.Y-4)*FZoom));Canvas.TextOut(OX+Round((S.Position.X-5)*FZoom),OY-Round((S.Position.Y+8)*FZoom),S.Ref+' '+S.Value);end;end;
procedure TSchematicCanvas.ZoomIn;begin FZoom:=Min(30,FZoom*1.25);Invalidate;end;procedure TSchematicCanvas.ZoomOut;begin FZoom:=Max(0.25,FZoom/1.25);Invalidate;end;
end.
