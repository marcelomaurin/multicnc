unit multicam_simulation_canvas;
{$mode objfpc}{$H+}
interface
uses Classes,Controls,Graphics,Math,multicam_stock_heightmap;
type TSimulationCanvas=class(TCustomControl)
 private FMap:TStockHeightMap;
 protected procedure Paint;override;
 public property HeightMap:TStockHeightMap read FMap write FMap;
 end;
implementation
procedure TSimulationCanvas.Paint;var C,R:Integer;Z,ZMin,ZMax,N:Double;V:Byte;RC:TRect;SX,SY:Double;
begin Canvas.Brush.Color:=clWhite;Canvas.FillRect(ClientRect);if(FMap=nil)or(FMap.Cols=0)or(FMap.Rows=0)then Exit;ZMin:=1E30;ZMax:=-1E30;for R:=0 to FMap.Rows-1 do for C:=0 to FMap.Cols-1 do begin Z:=FMap.Height(C,R);ZMin:=Min(ZMin,Z);ZMax:=Max(ZMax,Z);end;SX:=ClientWidth/FMap.Cols;SY:=ClientHeight/FMap.Rows;for R:=0 to FMap.Rows-1 do for C:=0 to FMap.Cols-1 do begin Z:=FMap.Height(C,R);if Abs(ZMax-ZMin)<1E-9 then N:=1 else N:=(Z-ZMin)/(ZMax-ZMin);V:=Round(40+N*200);Canvas.Brush.Color:=RGBToColor(V,V,V);Canvas.Pen.Style:=psClear;RC:=Rect(Round(C*SX),Round(R*SY),Round((C+1)*SX)+1,Round((R+1)*SY)+1);Canvas.FillRect(RC);end;Canvas.Pen.Style:=psSolid;end;
end.
