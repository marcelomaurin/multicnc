unit multicam_stock_heightmap;
{$mode objfpc}{$H+}
interface
uses Math,multicam_types;
type TStockHeightMap=class
 private FCols,FRows:Integer;FCell:Double;FStock:TStock;FZ:array of Double;function Idx(C,R:Integer):Integer;
 public procedure Init(const S:TStock;CellMM:Double);function Cols:Integer;function Rows:Integer;function Height(C,R:Integer):Double;procedure CutCircle(X,Y,Radius,BottomZ:Double);function RemovedVolumeMM3:Double;
 end;
implementation
function TStockHeightMap.Idx(C,R:Integer):Integer;begin Result:=R*FCols+C;end;
procedure TStockHeightMap.Init(const S:TStock;CellMM:Double);var I:Integer;begin FStock:=S;if CellMM<=0 then CellMM:=1;FCell:=CellMM;FCols:=Ceil(S.Width/FCell)+1;FRows:=Ceil(S.Height/FCell)+1;SetLength(FZ,FCols*FRows);for I:=0 to High(FZ)do FZ[I]:=S.TopZ;end;
function TStockHeightMap.Cols:Integer;begin Result:=FCols;end;function TStockHeightMap.Rows:Integer;begin Result:=FRows;end;function TStockHeightMap.Height(C,R:Integer):Double;begin Result:=FZ[Idx(C,R)];end;
procedure TStockHeightMap.CutCircle(X,Y,Radius,BottomZ:Double);var C,R:Integer;PX,PY:Double;begin for R:=0 to FRows-1 do for C:=0 to FCols-1 do begin PX:=FStock.OriginX+C*FCell;PY:=FStock.OriginY+R*FCell;if Sqr(PX-X)+Sqr(PY-Y)<=Sqr(Radius)then if FZ[Idx(C,R)]>BottomZ then FZ[Idx(C,R)]:=BottomZ;end;end;
function TStockHeightMap.RemovedVolumeMM3:Double;var I:Integer;begin Result:=0;for I:=0 to High(FZ)do Result:=Result+Max(0,FStock.TopZ-FZ[I])*FCell*FCell;end;
end.
