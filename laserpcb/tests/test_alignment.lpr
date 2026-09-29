program test_alignment;
{$mode objfpc}{$H+}
uses SysUtils,laserpcb_types,laserpcb_alignment;
var A,B:TFiducial;T:TAlignment2D;P,Q:TPathPoint;
begin A.DesignX:=0;A.DesignY:=0;A.MachineX:=10;A.MachineY:=20;B.DesignX:=100;B.DesignY:=0;B.MachineX:=110;B.MachineY:=20;T:=TAlignmentSolver.Solve2(A,B);if not T.Valid then Halt(1);P.X:=50;P.Y:=10;Q:=TAlignmentSolver.Apply(P,T);if Abs(Q.X-60)>0.001 then Halt(2);if Abs(Q.Y-30)>0.001 then Halt(3);Writeln('Alignment: OK');end.
