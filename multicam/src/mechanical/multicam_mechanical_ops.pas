unit multicam_mechanical_ops;
{$mode objfpc}{$H+}
interface
uses Math,multicam_types,multicam_job;
type TMechanicalOps=class public class procedure Slot(J:TCamJob;X1,Y1,X2,Y2,FinalDepth:Double);class procedure DrillPoint(J:TCamJob;X,Y,Depth:Double);class procedure RampEntry(J:TCamJob;X1,Y1,X2,Y2,TargetZ:Double;Steps:Integer);end;
implementation
class procedure TMechanicalOps.RampEntry(J:TCamJob;X1,Y1,X2,Y2,TargetZ:Double;Steps:Integer);var I:Integer;T:Double;begin if Steps<2 then Steps:=2;J.AddMove(X1,Y1,J.Settings.SafeZ,True);J.AddMove(X1,Y1,0,False);for I:=1 to Steps do begin T:=I/Steps;J.AddMove(X1+(X2-X1)*T,Y1+(Y2-Y1)*T,TargetZ*T,False);end;end;
class procedure TMechanicalOps.Slot(J:TCamJob;X1,Y1,X2,Y2,FinalDepth:Double);var Z:Double;begin J.Clear;if(J.Settings.StepDown<=0)or(FinalDepth>=0)then Exit;Z:=-J.Settings.StepDown;repeat if Z<FinalDepth then Z:=FinalDepth;RampEntry(J,X1,Y1,X2,Y2,Z,5);J.AddMove(X1,Y1,Z,False);J.AddMove(X1,Y1,J.Settings.SafeZ,True);Z:=Z-J.Settings.StepDown;until Z<FinalDepth;end;
class procedure TMechanicalOps.DrillPoint(J:TCamJob;X,Y,Depth:Double);begin J.Clear;if Depth>=0 then Exit;J.Operation:=coDrill;J.AddMove(X,Y,J.Settings.SafeZ,True);J.AddMove(X,Y,Depth,False);J.AddMove(X,Y,J.Settings.SafeZ,True);end;
end.
