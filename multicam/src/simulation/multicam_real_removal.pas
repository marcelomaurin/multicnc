unit multicam_real_removal;
{$mode objfpc}{$H+}
interface
uses Math,multicam_types,multicam_stock_heightmap,multicam_tool_shape;
type TRealMaterialRemoval=class
 public class procedure CutSegment(Map:TStockHeightMap;const A,B:TCamPoint;const Tool:TTool);static;
 end;
implementation
class procedure TRealMaterialRemoval.CutSegment(Map:TStockHeightMap;const A,B:TCamPoint;const Tool:TTool);
var D,T,X,Y,Z,Radius:Double;I,N:Integer;
begin if(Map=nil)or(Tool.Diameter<=0)then Exit;D:=Sqrt(Sqr(B.X-A.X)+Sqr(B.Y-A.Y)+Sqr(B.Z-A.Z));N:=Max(1,Ceil(D/Max(0.1,Tool.Diameter/8)));for I:=0 to N do begin T:=I/N;X:=A.X+(B.X-A.X)*T;Y:=A.Y+(B.Y-A.Y)*T;Z:=A.Z+(B.Z-A.Z)*T;Radius:=Tool.Diameter/2;case Tool.ToolType of ttBallNose:Radius:=Tool.Diameter/2;ttVBit:Radius:=Min(Tool.Diameter/2,Max(0.05,Abs(Z)));ttDrill:Radius:=Tool.Diameter/2;end;Map.CutCircle(X,Y,Radius,Z);end;end;
end.
