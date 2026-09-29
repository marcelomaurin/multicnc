program test_advanced_mechanical;
{$mode objfpc}{$H+}
uses multicam_types,multicam_job,multicam_geometry,multicam_advanced_ops;
var J:TCamJob;C:TCamContour;
begin J:=TCamJob.Create;C:=TCamContour.Create;try J.Settings.SafeZ:=5;J.Settings.StepDown:=1;C.Add(0,0);C.Add(40,0);C.Add(40,20);C.Add(0,20);C.Add(0,0);if not C.Closed then Halt(1);TAdvancedMechanicalCAM.Contour(J,C,-3,0.5,True);if J.Count=0 then Halt(2);J.Clear;TAdvancedMechanicalCAM.HelicalEntry(J,20,10,3,-2,2,16);if J.Count<30 then Halt(3);TAdvancedMechanicalCAM.AddTabs(J,C,-3,1,2);if J.Count=0 then Halt(4);Writeln('Advanced mechanical CAM: OK');finally C.Free;J.Free;end;end.
