program test_actuator_scheduler;
{$mode objfpc}{$H+}
uses Classes,multiphysics_graph,multiphysics_component_library,multiphysics_scheduler,multiphysics_runtime_types;
var G:TSimulationGraph;S:TGenericScheduler;L:TStringList;M:TSimComponent;X:TSimulationSnapshot;I:Integer;
begin G:=TSimulationGraph.Create;L:=TStringList.Create;try G.AddComponent(NewPowerSupply('PSU',24,10));M:=NewStepper('MX');M.Parameters.Values['steps_per_rev']:='200';M.Parameters.Values['microsteps']:='16';G.AddComponent(M);G.AddComponent(NewLeadScrew('SX',5));S:=TGenericScheduler.Create(G,L);try S.Start;for I:=1 to 100 do S.Step;X:=S.Snapshot;if X.Mechanical.Position<=0 then Halt(1);if X.Clock.Step<>100 then Halt(2);Writeln('PASS actuator scheduler pos=',X.Mechanical.Position:0:6);finally S.Free;end;finally L.Free;G.Free;end;end.
