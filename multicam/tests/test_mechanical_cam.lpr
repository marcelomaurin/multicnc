program test_mechanical_cam;
{$mode objfpc}{$H+}
uses multicam_types,multicam_job,multicam_mechanical;
var J:TCamJob;
begin J:=TCamJob.Create;try J.Tool.Diameter:=6;J.Settings.SafeZ:=5;J.Settings.StepDown:=1;J.Settings.StepOver:=0.4;TMechanicalCAM.Facing(J,0,0,50,30,-0.2);if J.Count=0 then Halt(1);TMechanicalCAM.Pocket(J,0,0,40,20,-3);if J.Count=0 then Halt(2);TMechanicalCAM.DrillGrid(J,5,5,10,10,3,2,-5);if J.Count<>18 then Halt(3);Writeln('Mechanical CAM: OK');finally J.Free;end;end.
