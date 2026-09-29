unit multicam_tool_shape;
{$mode objfpc}{$H+}
interface
uses Math,multicam_types,multicam_stock_heightmap;
type TToolShape=class
 public class function RadiusAtHeight(ToolType:TToolType;Radius,ZFromTip:Double):Double;static;
 end;
implementation
class function TToolShape.RadiusAtHeight(ToolType:TToolType;Radius,ZFromTip:Double):Double;
begin case ToolType of ttBallNose:if ZFromTip<=0 then Result:=0 else if ZFromTip>=Radius then Result:=Radius else Result:=Sqrt(Max(0,Sqr(Radius)-Sqr(Radius-ZFromTip)));ttVBit:Result:=Min(Radius,Max(0,ZFromTip));else Result:=Radius;end;end;
end.
