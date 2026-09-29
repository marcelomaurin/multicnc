unit multicam_advanced_ops;
{$mode objfpc}{$H+}
interface
uses Math,multicam_types,multicam_job,multicam_geometry;
type TAdvancedMechanicalCAM=class
 public class procedure HelicalEntry(J:TCamJob;CX,CY,Radius,TargetZ:Double;Turns,SegmentsPerTurn:Integer);class procedure Contour(J:TCamJob;C:TCamContour;FinalDepth,Allowance:Double;FinishPass:Boolean);class procedure AddTabs(J:TCamJob;C:TCamContour;Depth,TabHeight:Double;TabEveryNPoints:Integer);
 end;
implementation
class procedure TAdvancedMechanicalCAM.HelicalEntry(J:TCamJob;CX,CY,Radius,TargetZ:Double;Turns,SegmentsPerTurn:Integer);var I,N:Integer;A,T:Double;begin if(Turns<1)or(SegmentsPerTurn<8)or(Radius<=0)or(TargetZ>=0)then Exit;N:=Turns*SegmentsPerTurn;J.AddMove(CX+Radius,CY,J.Settings.SafeZ,True);for I:=1 to N do begin T:=I/N;A:=2*Pi*Turns*T;J.AddMove(CX+Cos(A)*Radius,CY+Sin(A)*Radius,TargetZ*T,False);end;end;
class procedure TAdvancedMechanicalCAM.Contour(J:TCamJob;C:TCamContour;FinalDepth,Allowance:Double;FinishPass:Boolean);var I:Integer;Z:Double;begin J.Clear;if(C=nil)or(C.Count<2)or(J.Settings.StepDown<=0)or(FinalDepth>=0)then Exit;J.Operation:=coProfileOutside;Z:=-J.Settings.StepDown;repeat if Z<FinalDepth then Z:=FinalDepth;J.AddMove(C.Point(0).X,C.Point(0).Y,J.Settings.SafeZ,True);J.AddMove(C.Point(0).X,C.Point(0).Y,Z,False);for I:=1 to C.Count-1 do J.AddMove(C.Point(I).X,C.Point(I).Y,Z,False);J.AddMove(C.Point(0).X,C.Point(0).Y,Z,False);J.AddMove(C.Point(0).X,C.Point(0).Y,J.Settings.SafeZ,True);Z:=Z-J.Settings.StepDown;until Z<FinalDepth;if FinishPass then begin J.AddMove(C.Point(0).X,C.Point(0).Y,FinalDepth,False);for I:=1 to C.Count-1 do J.AddMove(C.Point(I).X,C.Point(I).Y,FinalDepth,False);J.AddMove(C.Point(0).X,C.Point(0).Y,FinalDepth,False);J.AddMove(C.Point(0).X,C.Point(0).Y,J.Settings.SafeZ,True);end;end;
class procedure TAdvancedMechanicalCAM.AddTabs(J:TCamJob;C:TCamContour;Depth,TabHeight:Double;TabEveryNPoints:Integer);var I:Integer;Z:Double;begin if(C=nil)or(TabEveryNPoints<1)then Exit;J.Clear;J.AddMove(C.Point(0).X,C.Point(0).Y,J.Settings.SafeZ,True);for I:=0 to C.Count-1 do begin Z:=Depth;if(I mod TabEveryNPoints)=0 then Z:=Depth+TabHeight;J.AddMove(C.Point(I).X,C.Point(I).Y,Z,False);end;J.AddMove(C.Point(0).X,C.Point(0).Y,J.Settings.SafeZ,True);end;
end.
