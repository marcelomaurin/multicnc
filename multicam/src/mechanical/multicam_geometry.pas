unit multicam_geometry;
{$mode objfpc}{$H+}
interface
uses multicam_types;
type TCamContour=class
 private FPoints:array of TCamPoint;
 public procedure Clear;procedure Add(X,Y:Double);function Count:Integer;function Point(I:Integer):TCamPoint;function Closed:Boolean;
 end;
implementation
procedure TCamContour.Clear;begin SetLength(FPoints,0);end;
procedure TCamContour.Add(X,Y:Double);var N:Integer;begin N:=Length(FPoints);SetLength(FPoints,N+1);FPoints[N].X:=X;FPoints[N].Y:=Y;FPoints[N].Z:=0;end;
function TCamContour.Count:Integer;begin Result:=Length(FPoints);end;function TCamContour.Point(I:Integer):TCamPoint;begin Result:=FPoints[I];end;
function TCamContour.Closed:Boolean;begin Result:=(Count>2)and(Abs(FPoints[0].X-FPoints[Count-1].X)<1e-6)and(Abs(FPoints[0].Y-FPoints[Count-1].Y)<1e-6);end;
end.
