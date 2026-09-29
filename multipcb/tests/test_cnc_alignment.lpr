program test_cnc_alignment;
{$mode objfpc}{$H+}
uses SysUtils,multipcb_cnc_position,multipcb_cnc_alignment;
var D1,D2,M1,M2,P,Q:TPCBPoint;A:TPCBAlignment;
begin D1.X:=0;D1.Y:=0;D2.X:=100;D2.Y:=0;M1.X:=10;M1.Y:=20;M2.X:=110;M2.Y:=20;A:=TPCBAlignmentSolver.Solve2(D1,D2,M1,M2);if not A.Valid then Halt(1);P.X:=50;P.Y:=10;Q:=TPCBAlignmentSolver.Apply(P,A);if Abs(Q.X-60)>0.001 then Halt(2);if Abs(Q.Y-30)>0.001 then Halt(3);Writeln('PCB CNC alignment: OK');end.
