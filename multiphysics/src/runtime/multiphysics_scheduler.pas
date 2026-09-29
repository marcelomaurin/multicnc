unit multiphysics_scheduler;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,multiphysics_graph,multiphysics_runtime_types,multiphysics_motion_models,multiphysics_mna;
type
 TDomainPhase=(dpElectrical,dpControl,dpActuators,dpMechanical,dpThermal,dpSensors,dpProtection);
 TGenericScheduler=class
 private FGraph:TSimulationGraph;FClock:TSimulationClock;FMNA:TMNASolver;FLog:TStrings;FLast:TSimulationSnapshot;
  procedure ElectricalPhase;procedure ControlPhase;procedure ActuatorPhase;procedure MechanicalPhase;procedure ThermalPhase;procedure SensorPhase;procedure ProtectionPhase;
 public constructor Create(G:TSimulationGraph;Log:TStrings);destructor Destroy;override;procedure Reset;procedure Start;procedure Stop;procedure Step;property Snapshot:TSimulationSnapshot read FLast;
 end;
implementation
constructor TGenericScheduler.Create(G:TSimulationGraph;Log:TStrings);begin inherited Create;FGraph:=G;FLog:=Log;FMNA:=TMNASolver.Create;Reset;end;destructor TGenericScheduler.Destroy;begin FMNA.Free;inherited;end;
procedure TGenericScheduler.Reset;begin FillChar(FLast,SizeOf(FLast),0);FClock.Dt:=0.001;FClock.State:=simStopped;FLast.Thermal.AmbientTemperature:=20;FLast.Thermal.Temperature:=20;end;
procedure TGenericScheduler.Start;begin FClock.State:=simRunning;end;procedure TGenericScheduler.Stop;begin FClock.State:=simStopped;end;
procedure TGenericScheduler.ElectricalPhase;var I:Integer;C:TSimComponent;V,R:Double;VCC,N:Integer;begin FMNA.Clear;VCC:=FMNA.AddNode('BUS');V:=0;for I:=0 to FGraph.ComponentCount-1 do begin C:=FGraph.ComponentAt(I);if C.Kind=ckPowerSupply then V:=StrToFloatDef(C.Parameters.Values['voltage'],24);end;if V=0 then Exit;FMNA.AddVoltageSource(VCC,0,V);for I:=0 to FGraph.ComponentCount-1 do begin C:=FGraph.ComponentAt(I);if C.Kind=ckResistor then begin R:=StrToFloatDef(C.Parameters.Values['resistance'],1000);FMNA.AddResistor(VCC,0,R);end;end;if FMNA.Solve then begin FLast.Electrical.SupplyVoltage:=V;FLast.Electrical.BusVoltage:=FMNA.NodeVoltage(VCC);FLast.Electrical.TotalCurrent:=Abs(FMNA.SourceCurrent(0));FLast.Electrical.ElectricalPower:=FLast.Electrical.BusVoltage*FLast.Electrical.TotalCurrent;end else FLog.Add('MNA: '+FMNA.LastError);end;
procedure TGenericScheduler.ControlPhase;begin if FLast.Control.Enabled then FLast.Control.PWM:=1;end;
procedure TGenericScheduler.ActuatorPhase;begin end;
procedure TGenericScheduler.MechanicalPhase;begin FLast.Mechanical.Position:=FLast.Mechanical.Position+FLast.Mechanical.Velocity*FClock.Dt;end;
procedure TGenericScheduler.ThermalPhase;begin if FLast.Thermal.Temperature=0 then FLast.Thermal.Temperature:=FLast.Thermal.AmbientTemperature;end;
procedure TGenericScheduler.SensorPhase;begin FLast.Control.SensorValue:=FLast.Mechanical.Position;end;
procedure TGenericScheduler.ProtectionPhase;begin if FLast.Thermal.Temperature>120 then begin FLast.Control.Enabled:=False;FLast.Control.PWM:=0;end;end;
procedure TGenericScheduler.Step;begin if FClock.State<>simRunning then Exit;ElectricalPhase;ControlPhase;ActuatorPhase;MechanicalPhase;ThermalPhase;SensorPhase;ProtectionPhase;FClock.Time:=FClock.Time+FClock.Dt;Inc(FClock.Step);FLast.Clock:=FClock;end;
end.
