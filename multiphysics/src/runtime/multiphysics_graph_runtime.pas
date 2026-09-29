unit multiphysics_graph_runtime;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,multiphysics_graph,multiphysics_component_library,multiphysics_runtime,multiphysics_runtime_types;
type
 TGraphRuntime=class
 private FGraph:TSimulationGraph;FEngine:TSimulationRuntime;FLog:TStrings;function HasKind(K:TComponentKind):Boolean;
 public constructor Create(AGraph:TSimulationGraph;ALog:TStrings);destructor Destroy;override;function Prepare:Boolean;procedure Start;procedure Pause;procedure Stop;procedure Step;function Snapshot:TSimulationSnapshot;
 end;
function BuildDemoMachine:TSimulationGraph;
implementation
constructor TGraphRuntime.Create(AGraph:TSimulationGraph;ALog:TStrings);begin inherited Create;FGraph:=AGraph;FLog:=ALog;FEngine:=TSimulationRuntime.Create;end;
destructor TGraphRuntime.Destroy;begin FEngine.Free;inherited;end;
function TGraphRuntime.HasKind(K:TComponentKind):Boolean;var I:Integer;begin Result:=False;for I:=0 to FGraph.ComponentCount-1 do if FGraph.ComponentAt(I).Kind=K then Exit(True);end;
function TGraphRuntime.Prepare:Boolean;begin Result:=FGraph.Validate(FLog);if not Result then Exit;Result:=HasKind(ckPowerSupply)and HasKind(ckPWMDriver)and HasKind(ckDCMotor)and HasKind(ckAxisLoad)and HasKind(ckSpeedSensor)and HasKind(ckController);if not Result then FLog.Add('ERRO: cadeia minima fonte-driver-motor-carga-sensor-controlador incompleta')else FLog.Add('Runtime preparado a partir da topologia da montagem');end;
procedure TGraphRuntime.Start;begin FEngine.Start;end;procedure TGraphRuntime.Pause;begin FEngine.Pause;end;procedure TGraphRuntime.Stop;begin FEngine.Stop;end;procedure TGraphRuntime.Step;begin FEngine.Step;end;function TGraphRuntime.Snapshot:TSimulationSnapshot;begin Result:=FEngine.Snapshot;end;
function BuildDemoMachine:TSimulationGraph;var G:TSimulationGraph;begin G:=TSimulationGraph.Create;G.AddComponent(NewPowerSupply('PSU1',24,10));G.AddComponent(NewPWMDriver('DRV1'));G.AddComponent(NewDCMotor('M1'));G.AddComponent(NewAxisLoad('LOAD1'));G.AddComponent(NewSpeedSensor('S1'));G.AddComponent(NewController('CTRL1'));G.Connect('PSU1','V+','DRV1','VIN',ptElectrical);G.Connect('DRV1','VOUT','M1','PWR',ptElectrical);G.Connect('M1','SHAFT','LOAD1','SHAFT',ptMechanicalRotary);G.Connect('M1','SHAFT','S1','SHAFT',ptMechanicalRotary);G.Connect('S1','OUT','CTRL1','SENSOR',ptSignal);G.Connect('CTRL1','PWM','DRV1','CMD',ptSignal);Result:=G;end;
end.
