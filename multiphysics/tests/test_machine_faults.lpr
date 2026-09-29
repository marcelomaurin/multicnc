program test_machine_faults;
{$mode objfpc}{$H+}
uses multiphysics_machine_runtime,multiphysics_machine_faults;
var M:TMachineRuntime;A:TAxisRuntime;I:Int64;
begin M:=TMachineRuntime.Create;try A:=M.AddAxis('X',0,300,80,1);M.CommandAxis('X',100,50);M.Start;InjectAxisFault(A,mfAxisLocked);for I:=1 to 100 do M.Step;if A.Motor.LostSteps=0 then Halt(1);InjectAxisFault(A,mfOpenCircuit);if A.Command.Enabled then Halt(2);InjectAxisFault(A,mfLimitStuck);if not A.State.AtMin then Halt(3);Writeln('PASS machine faults');finally M.Free;end;end.
