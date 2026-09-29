program test_electronics_simulation;
{$mode objfpc}{$H+}
uses multicam_types,multicam_electronics_types,multicam_electronics_model;
var E:TElectronicsModel;C:TElectronicsConfig;P:TCamPoint;
begin E:=TElectronicsModel.Create;try C.StepsPerMMX:=80;C.StepsPerMMY:=80;C.StepsPerMMZ:=400;C.MotorSupplyV:=24;C.LogicSupplyV:=5;C.MaxMotorCurrentA:=3;E.Configure(C);P.X:=0;P.Y:=0;P.Z:=0;E.ApplyMove(P,False,0);P.X:=10;P.Y:=5;P.Z:=-1;E.ApplyMove(P,True,12000);if E.State.X.PulseCount<>800 then Halt(1);if E.State.Y.PulseCount<>400 then Halt(2);if E.State.Z.PulseCount<>400 then Halt(3);if not E.State.Spindle.Enable then Halt(4);E.SetEStop(True);if not E.HasFault then Halt(5);Writeln('Electronic simulation: OK');finally E.Free;end;end.
