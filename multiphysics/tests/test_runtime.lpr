program test_runtime;
{$mode objfpc}{$H+}
uses multiphysics_runtime,multiphysics_runtime_types;
var R:TSimulationRuntime;S:TSimulationSnapshot;I:Integer;
begin R:=TSimulationRuntime.Create;try R.Start;for I:=1 to 1000 do R.Step;S:=R.Snapshot;if S.Clock.Step<>1000 then Halt(1);if S.Electrical.TotalCurrent<=0 then Halt(2);if S.Mechanical.Velocity<=0 then Halt(3);if S.Thermal.Temperature<=20 then Halt(4);if S.Control.SensorValue<>S.Mechanical.Velocity then Halt(5);Writeln('PASS coupled runtime t=',S.Clock.Time:0:2,' V=',S.Electrical.BusVoltage:0:2,' I=',S.Electrical.TotalCurrent:0:2,' speed=',S.Mechanical.Velocity:0:2,' temp=',S.Thermal.Temperature:0:2);finally R.Free;end;end.
