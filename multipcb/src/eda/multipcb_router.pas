unit multipcb_router;
{$mode objfpc}{$H+}
interface
uses Math,multipcb_types,multipcb_board;
type TRoutingMode=(rmOrthogonal,rm45Degree);
 TInteractiveRouter=class
 public class procedure Route(Board:TBoard;const A,B:TPointMM;Width:Double;Layer:TPCBLayer;const Net:string;Mode:TRoutingMode);
 end;
implementation
class procedure TInteractiveRouter.Route(Board:TBoard;const A,B:TPointMM;Width:Double;Layer:TPCBLayer;const Net:string;Mode:TRoutingMode);
var M:TPointMM;D:Double;
begin if Mode=rmOrthogonal then begin M.X:=B.X;M.Y:=A.Y;Board.AddTrack(A.X,A.Y,M.X,M.Y,Width,Layer,Net);Board.AddTrack(M.X,M.Y,B.X,B.Y,Width,Layer,Net);end else begin D:=Min(Abs(B.X-A.X),Abs(B.Y-A.Y));M.X:=A.X+Sign(B.X-A.X)*D;M.Y:=A.Y+Sign(B.Y-A.Y)*D;Board.AddTrack(A.X,A.Y,M.X,M.Y,Width,Layer,Net);Board.AddTrack(M.X,M.Y,B.X,B.Y,Width,Layer,Net);end;end;
end.
