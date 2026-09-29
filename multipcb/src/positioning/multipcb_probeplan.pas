unit multipcb_probeplan;
{$mode objfpc}{$H+}
interface
uses multipcb_cnc_position;
type
 TProbeTarget=record X,Y:Double;end;
 TProbePlan=class
 private FTargets:array of TProbeTarget;
 public procedure BuildGrid(P:TPCBPlacement;Cols,Rows:Integer;Margin:Double);function Count:Integer;function Target(I:Integer):TProbeTarget;
 end;
implementation
procedure TProbePlan.BuildGrid(P:TPCBPlacement;Cols,Rows:Integer;Margin:Double);
var C,R,N:Integer;Q:TPCBPoint;SX,SY:Double;
begin SetLength(FTargets,0);if(Cols<2)or(Rows<2)or(P.BoardWidth<=2*Margin)or(P.BoardHeight<=2*Margin)then Exit;SX:=(P.BoardWidth-2*Margin)/(Cols-1);SY:=(P.BoardHeight-2*Margin)/(Rows-1);N:=0;SetLength(FTargets,Cols*Rows);for R:=0 to Rows-1 do for C:=0 to Cols-1 do begin Q.X:=Margin+C*SX;Q.Y:=Margin+R*SY;Q:=P.Transform(Q);FTargets[N].X:=Q.X;FTargets[N].Y:=Q.Y;Inc(N);end;end;
function TProbePlan.Count:Integer;begin Result:=Length(FTargets);end;
function TProbePlan.Target(I:Integer):TProbeTarget;begin Result:=FTargets[I];end;
end.
