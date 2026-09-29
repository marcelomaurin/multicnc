unit multiphysics_faults;
{$mode objfpc}{$H+}
interface
uses multiphysics_runtime_types,multiphysics_components;
type TFaultKind=(fkNone,fkOpenCircuit,fkShortCircuit,fkMotorLocked,fkSensorFailure,fkOverTemperature);
 TFaultState=record Kind:TFaultKind;Active:Boolean;TripTemperature:Double;end;
procedure ApplyFault(const F:TFaultState;var S:TSimulationSnapshot;var Load:TAxisLoad);
implementation
procedure ApplyFault(const F:TFaultState;var S:TSimulationSnapshot;var Load:TAxisLoad);begin if not F.Active then Exit;case F.Kind of fkOpenCircuit:begin S.Control.Enabled:=False;S.Control.PWM:=0;end;fkShortCircuit:S.Control.PWM:=1;fkMotorLocked:begin Load.ExternalTorque:=1e6;S.Mechanical.Velocity:=0;end;fkSensorFailure:S.Control.SensorValue:=0;fkOverTemperature:if S.Thermal.Temperature>=F.TripTemperature then begin S.Control.Enabled:=False;S.Control.PWM:=0;end;end;end;
end.
