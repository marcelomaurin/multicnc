program test_mechanical_setup;
{$mode objfpc}{$H+}
uses Classes,multicam_types,multicam_job,multicam_setup,multicam_mechanical_ops;
var J:TCamJob;S:TMechanicalSetup;E:TStringList;
begin J:=TCamJob.Create;S:=TMechanicalSetup.Create;E:=TStringList.Create;try J.Settings.SafeZ:=5;J.Settings.StepDown:=1;S.Stock.Width:=100;S.Stock.Height:=80;S.Stock.OriginX:=0;S.Stock.OriginY:=0;S.AddFixture('Grampo',40,0,20,10,8);TMechanicalOps.DrillPoint(J,20,20,-3);if not S.ValidatePath(J,E)then Halt(1);E.Clear;TMechanicalOps.DrillPoint(J,45,5,-3);if S.ValidatePath(J,E)then Halt(2);Writeln('Mechanical setup: OK');finally E.Free;S.Free;J.Free;end;end.
