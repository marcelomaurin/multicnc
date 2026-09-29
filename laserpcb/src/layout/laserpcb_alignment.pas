unit laserpcb_alignment;
{$mode objfpc}{$H+}
interface
uses Math,laserpcb_types;
type
 TFiducial=record DesignX,DesignY,MachineX,MachineY:Double;end;
 TAlignment2D=record Scale,RotationDeg,OffsetX,OffsetY:Double;Valid:Boolean;end;
 TAlignmentSolver=class public class function Solve2(const A,B:TFiducial):TAlignment2D;class function Apply(const P:TPathPoint;const T:TAlignment2D):TPathPoint;end;
implementation
class function TAlignmentSolver.Solve2(const A,B:TFiducial):TAlignment2D;
var DX,DY,MX,MY,LD,LM,AD,AM:Double;
begin FillChar(Result,SizeOf(Result),0);DX:=B.DesignX-A.DesignX;DY:=B.DesignY-A.DesignY;MX:=B.MachineX-A.MachineX;MY:=B.MachineY-A.MachineY;LD:=Hypot(DX,DY);LM:=Hypot(MX,MY);if(LD<1e-9)or(LM<1e-9)then Exit;Result.Scale:=LM/LD;AD:=ArcTan2(DY,DX);AM:=ArcTan2(MY,MX);Result.RotationDeg:=RadToDeg(AM-AD);Result.OffsetX:=A.MachineX-Result.Scale*(A.DesignX*Cos(AM-AD)-A.DesignY*Sin(AM-AD));Result.OffsetY:=A.MachineY-Result.Scale*(A.DesignX*Sin(AM-AD)+A.DesignY*Cos(AM-AD));Result.Valid:=True;end;
class function TAlignmentSolver.Apply(const P:TPathPoint;const T:TAlignment2D):TPathPoint;
var R:Double;begin Result:=P;if not T.Valid then Exit;R:=DegToRad(T.RotationDeg);Result.X:=T.OffsetX+T.Scale*(P.X*Cos(R)-P.Y*Sin(R));Result.Y:=T.OffsetY+T.Scale*(P.X*Sin(R)+P.Y*Cos(R));end;
end.
