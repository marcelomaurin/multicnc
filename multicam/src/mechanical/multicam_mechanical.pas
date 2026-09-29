unit multicam_mechanical;
{$mode objfpc}{$H+}
interface
uses SysUtils,Math,multicam_types,multicam_job;
type TMechanicalSetup=record Stock:TStock;WorkZero:TCamPoint;ClearanceZ:Double;end;
 TMechanicalCAM=class
 public class procedure Facing(J:TCamJob;X,Y,W,H,Depth:Double);
 class procedure Pocket(J:TCamJob;X,Y,W,H,FinalDepth:Double);
 class procedure DrillGrid(J:TCamJob;X0,Y0,DX,DY:Double;Cols,Rows:Integer;Depth:Double);
 end;
implementation
class procedure TMechanicalCAM.Facing(J:TCamJob;X,Y,W,H,Depth:Double);
var YY,Step:Double;Dir:Boolean;
begin J.Clear;J.Operation:=coFacing;if(J.Tool.Diameter<=0)or(J.Settings.StepOver<=0)then Exit;Step:=J.Tool.Diameter*J.Settings.StepOver;if Step<=0 then Exit;J.AddMove(X,Y,J.Settings.SafeZ,True);J.AddMove(X,Y,Depth,False);YY:=Y;Dir:=True;while YY<=Y+H do begin if Dir then J.AddMove(X+W,YY,Depth,False) else J.AddMove(X,YY,Depth,False);YY:=YY+Step;if YY<=Y+H then begin if Dir then J.AddMove(X+W,YY,Depth,False)else J.AddMove(X,YY,Depth,False);end;Dir:=not Dir;end;J.AddMove(X,Y,J.Settings.SafeZ,True);end;
class procedure TMechanicalCAM.Pocket(J:TCamJob;X,Y,W,H,FinalDepth:Double);
var Z,Inset,Step,MaxInset:Double;
begin J.Clear;J.Operation:=coPocket;if(J.Tool.Diameter<=0)or(J.Settings.StepDown<=0)or(J.Settings.StepOver<=0)then Exit;Step:=J.Tool.Diameter*J.Settings.StepOver;MaxInset:=Min(W,H)/2-J.Tool.Diameter/2;if MaxInset<0 then Exit;Z:=-J.Settings.StepDown;repeat if Z<FinalDepth then Z:=FinalDepth;Inset:=J.Tool.Diameter/2;J.AddMove(X+Inset,Y+Inset,J.Settings.SafeZ,True);J.AddMove(X+Inset,Y+Inset,Z,False);while Inset<=MaxInset do begin J.AddMove(X+W-Inset,Y+Inset,Z,False);J.AddMove(X+W-Inset,Y+H-Inset,Z,False);J.AddMove(X+Inset,Y+H-Inset,Z,False);J.AddMove(X+Inset,Y+Inset,Z,False);Inset:=Inset+Step;end;J.AddMove(X+J.Tool.Diameter/2,Y+J.Tool.Diameter/2,J.Settings.SafeZ,True);Z:=Z-J.Settings.StepDown;until Z<FinalDepth;end;
class procedure TMechanicalCAM.DrillGrid(J:TCamJob;X0,Y0,DX,DY:Double;Cols,Rows:Integer;Depth:Double);
var C,R:Integer;X,Y:Double;
begin J.Clear;J.Operation:=coDrill;if(Cols<1)or(Rows<1)or(Depth>=0)then Exit;for R:=0 to Rows-1 do for C:=0 to Cols-1 do begin X:=X0+C*DX;Y:=Y0+R*DY;J.AddMove(X,Y,J.Settings.SafeZ,True);J.AddMove(X,Y,Depth,False);J.AddMove(X,Y,J.Settings.SafeZ,True);end;end;
end.
