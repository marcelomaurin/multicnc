program test_integration_suite;
{$mode objfpc}{$H+}
uses Classes,SysUtils,multiphysics_graph,multiphysics_graph_runtime,multiphysics_cnc_reference,multiphysics_runtime_types,multiphysics_instruments,multiphysics_coupling;
var G:TSimulationGraph;R:TGraphRuntime;L:TStringList;Rec:TTelemetryRecorder;S:TSimulationSnapshot;F:TFieldLoads;I:Integer;
begin L:=TStringList.Create;G:=BuildReferenceCNC;R:=TGraphRuntime.Create(G,L);Rec:=TTelemetryRecorder.Create;try if not R.Prepare then Halt(1);if G.Find('MOTOR_X')=nil then Halt(2);R.Start;for I:=1 to 1000 do begin R.Step;if (I mod 10)=0 then Rec.Sample(R.Snapshot);end;S:=R.Snapshot;if S.Electrical.TotalCurrent<=0 then Halt(3);if S.Mechanical.Velocity<=0 then Halt(4);if S.Thermal.Temperature<=20 then Halt(5);F:=RuntimeToFieldLoads(S);if F.Torque=0 then Halt(6);if Rec.Lines.Count<50 then Halt(7);Writeln('PASS integrated CNC machine components=',G.ComponentCount,' telemetry=',Rec.Lines.Count);finally Rec.Free;R.Free;G.Free;L.Free;end;end.
