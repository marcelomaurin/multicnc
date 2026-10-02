unit multicam_stock_heightmap;
{$mode objfpc}{$H+}
interface
uses Math,multicam_types;
type TStockHeightMap=class
 private FCols,FRows:Integer;FCell:Double;FStock:TStock;FZ:array of Double;function Idx(C,R:Integer):Integer;
 public procedure Init(const S:TStock;CellMM:Double);function Cols:Integer;function Rows:Integer;function Height(C,R:Integer):Double;procedure CutCircle(X,Y,Radius,BottomZ:Double);function RemovedVolumeMM3:Double;function BottomZ:Double;property CellMM:Double read FCell;
 end;
implementation
function TStockHeightMap.Idx(C,R:Integer):Integer;begin Result:=R*FCols+C;end;
procedure TStockHeightMap.Init(const S:TStock;CellMM:Double);var I:Integer;begin FStock:=S;if CellMM<=0 then CellMM:=1;FCell:=CellMM;FCols:=Max(1,Ceil(S.Width/FCell));FRows:=Max(1,Ceil(S.Height/FCell));SetLength(FZ,FCols*FRows);for I:=0 to High(FZ)do FZ[I]:=S.TopZ;end;
function TStockHeightMap.Cols:Integer;begin Result:=FCols;end;function TStockHeightMap.Rows:Integer;begin Result:=FRows;end;function TStockHeightMap.Height(C,R:Integer):Double;begin Result:=FZ[Idx(C,R)];end;function TStockHeightMap.BottomZ:Double;begin Result:=FStock.TopZ-FStock.Thickness;end;
procedure TStockHeightMap.CutCircle(X,Y,Radius,BottomZ:Double);var C,R,C0,C1,R0,R1:Integer;PX,PY,ZMin:Double;begin if Radius<=0 then Exit;if FStock.Thickness>0 then ZMin:=Max(BottomZ,Self.BottomZ) else ZMin:=BottomZ;{ espessura 0 = sem piso conhecido }C0:=Max(0,Floor((X-Radius-FStock.OriginX)/FCell));C1:=Min(FCols-1,Ceil((X+Radius-FStock.OriginX)/FCell));R0:=Max(0,Floor((Y-Radius-FStock.OriginY)/FCell));R1:=Min(FRows-1,Ceil((Y+Radius-FStock.OriginY)/FCell));for R:=R0 to R1 do for C:=C0 to C1 do begin PX:=FStock.OriginX+(C+0.5)*FCell;PY:=FStock.OriginY+(R+0.5)*FCell;if Sqr(PX-X)+Sqr(PY-Y)<=Sqr(Radius)then if FZ[Idx(C,R)]>ZMin then FZ[Idx(C,R)]:=ZMin;end;end;
function TStockHeightMap.RemovedVolumeMM3:Double;var I:Integer;begin Result:=0;for I:=0 to High(FZ)do Result:=Result+Max(0,FStock.TopZ-FZ[I])*FCell*FCell;end;
end.
