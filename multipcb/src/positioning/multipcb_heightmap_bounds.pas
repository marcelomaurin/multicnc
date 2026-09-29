unit multipcb_heightmap_bounds;
{$mode objfpc}{$H+}
interface
uses Math,multipcb_heightmap;
type THeightMapBounds=record MinX,MinY,MaxX,MaxY:Double;Valid:Boolean;end;
function GetHeightMapBounds(H:THeightMap):THeightMapBounds;
function PointInsideHeightMap(H:THeightMap;X,Y:Double):Boolean;
implementation
function GetHeightMapBounds(H:THeightMap):THeightMapBounds;
var I:Integer;P:TProbePoint;
begin FillChar(Result,SizeOf(Result),0);if not Assigned(H)or(H.Count=0)then Exit;P:=H.Point(0);Result.MinX:=P.X;Result.MaxX:=P.X;Result.MinY:=P.Y;Result.MaxY:=P.Y;for I:=1 to H.Count-1 do begin P:=H.Point(I);Result.MinX:=Min(Result.MinX,P.X);Result.MaxX:=Max(Result.MaxX,P.X);Result.MinY:=Min(Result.MinY,P.Y);Result.MaxY:=Max(Result.MaxY,P.Y);end;Result.Valid:=True;end;
function PointInsideHeightMap(H:THeightMap;X,Y:Double):Boolean;var B:THeightMapBounds;begin B:=GetHeightMapBounds(H);Result:=B.Valid and(X>=B.MinX)and(X<=B.MaxX)and(Y>=B.MinY)and(Y<=B.MaxY);end;
end.
