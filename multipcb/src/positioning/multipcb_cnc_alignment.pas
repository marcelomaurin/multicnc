unit multipcb_cnc_alignment;
{$mode objfpc}{$H+}
interface
uses Math,multipcb_cnc_position;
type TPCBAlignment=record Scale,RotationDeg,OffsetX,OffsetY:Double;Valid:Boolean;end;
type TPCBAlignmentSolver=class public class function Solve2(const D1,D2,M1,M2:TPCBPoint):TPCBAlignment;class function Apply(const P:TPCBPoint;const A:TPCBAlignment):TPCBPoint;end;
implementation
class function TPCBAlignmentSolver.Solve2(const D1,D2,M1,M2:TPCBPoint):TPCBAlignment;var DX,DY,MX,MY,LD,LM,R:Double;
begin FillChar(Result,SizeOf(Result),0);DX:=D2.X-D1.X;DY:=D2.Y-D1.Y;MX:=M2.X-M1.X;MY:=M2.Y-M1.Y;LD:=Hypot(DX,DY);LM:=Hypot(MX,MY);if(LD<1e-9)or(LM<1e-9)then Exit;Result.Scale:=LM/LD;R:=ArcTan2(MY,MX)-ArcTan2(DY,DX);Result.RotationDeg:=RadToDeg(R);Result.OffsetX:=M1.X-Result.Scale*(D1.X*Cos(R)-D1.Y*Sin(R));Result.OffsetY:=M1.Y-Result.Scale*(D1.X*Sin(R)+D1.Y*Cos(R));Result.Valid:=True;end;
class function TPCBAlignmentSolver.Apply(const P:TPCBPoint;const A:TPCBAlignment):TPCBPoint;var R:Double;begin Result:=P;if not A.Valid then Exit;R:=DegToRad(A.RotationDeg);Result.X:=A.OffsetX+A.Scale*(P.X*Cos(R)-P.Y*Sin(R));Result.Y:=A.OffsetY+A.Scale*(P.X*Sin(R)+P.Y*Cos(R));end;
end.
