program test_calibration_matrix;
{$mode objfpc}{$H+}
uses laserpcb_job,laserpcb_types,laserart_calibration;
var J:TLaserPCBJob;A,B:TPathPoint;
begin J:=TLaserPCBJob.Create;try TLaserCalibration.BuildMatrix(J,0,0,10,10,100,500,600,1800,3,3);if J.Count=0 then Halt(1);A:=J.Point(1);B:=J.Point(7);if A.Power=B.Power then Halt(2);A:=J.Point(1);B:=J.Point(19);if A.Feed=B.Feed then Halt(3);Writeln('Laser calibration matrix: OK');finally J.Free;end;end.
