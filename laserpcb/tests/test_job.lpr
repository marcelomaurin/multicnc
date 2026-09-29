program test_job;
{$mode objfpc}{$H+}
uses SysUtils,laserpcb_types,laserpcb_job;
var J:TLaserPCBJob;P:TPathPoint;
begin J:=TLaserPCBJob.Create;try J.Width:=100;J.AddPoint(10,20,False);J.AddPoint(30,20,True);if J.Count<>2 then Halt(1);J.Mirror:=True;J.ApplyBottomMirror;P:=J.Point(0);if Abs(P.X-90)>0.001 then Halt(2);Writeln('LaserPCB job: OK');finally J.Free;end;end.
