program test_graph_runtime;
{$mode objfpc}{$H+}
uses Classes,multiphysics_graph,multiphysics_graph_runtime,multiphysics_runtime_types;
var G:TSimulationGraph;R:TGraphRuntime;L:TStringList;S:TSimulationSnapshot;I:Integer;
begin L:=TStringList.Create;G:=BuildDemoMachine;R:=TGraphRuntime.Create(G,L);try if not R.Prepare then Halt(1);if G.ComponentCount<>6 then Halt(2);if G.ConnectionCount<>6 then Halt(3);R.Start;for I:=1 to 500 do R.Step;S:=R.Snapshot;if S.Electrical.TotalCurrent<=0 then Halt(4);if S.Mechanical.Velocity<=0 then Halt(5);Writeln('PASS graph runtime components=',G.ComponentCount,' links=',G.ConnectionCount);finally R.Free;G.Free;L.Free;end;end.
