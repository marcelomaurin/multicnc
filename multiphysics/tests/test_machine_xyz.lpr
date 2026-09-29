program test_machine_xyz;
{$mode objfpc}{$H+}
uses Math,multiphysics_machine_runtime;
var M:TMachineRuntime;I:Integer;
begin M:=TMachineRuntime.Create;try M.AddAxis('X',0,300,80,1.2);M.AddAxis('Y',0,200,80,1.2);M.AddAxis('Z',0,100,400,1.5);M.CommandAxis('X',100,50);M.CommandAxis('Y',50,40);M.CommandAxis('Z',20,10);M.SetSpindle(12000);M.Start;for I:=1 to 20000 do M.Step;if Abs(M.Axis(0).State.PositionMM-100)>0.05 then Halt(1);if Abs(M.Axis(1).State.PositionMM-50)>0.05 then Halt(2);if Abs(M.Axis(2).State.PositionMM-20)>0.05 then Halt(3);if M.SpindleRPM<11000 then Halt(4);Writeln('PASS CNC XYZ + spindle');finally M.Free;end;end.
