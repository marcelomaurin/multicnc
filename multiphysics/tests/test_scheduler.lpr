program test_scheduler;
{$mode objfpc}{$H+}
uses Classes,multiphysics_graph,multiphysics_component_library,multiphysics_scheduler,multiphysics_runtime_types;
var G:TSimulationGraph;S:TGenericScheduler;L:TStringList;R:TSimComponent;X:TSimulationSnapshot;I:Integer;
begin G:=TSimulationGraph.Create;L:=TStringList.Create;try G.AddComponent(NewPowerSupply('PSU',12,5));R:=NewResistor('R1',120);G.AddComponent(R);S:=TGenericScheduler.Create(G,L);try S.Start;for I:=1 to 10 do S.Step;X:=S.Snapshot;if Abs(X.Electrical.BusVoltage-12)>1e-6 then Halt(1);if Abs(X.Electrical.TotalCurrent-0.1)>1e-6 then Halt(2);if X.Clock.Step<>10 then Halt(3);Writeln('PASS scheduler V=',X.Electrical.BusVoltage:0:2,' I=',X.Electrical.TotalCurrent:0:3);finally S.Free;end;finally L.Free;G.Free;end;end.
