unit multiphysics_instruments;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,multiphysics_runtime_types;
type TInstrumentKind=(ikVoltmeter,ikAmmeter,ikPowerMeter,ikTachometer,ikTorqueMeter,ikThermometer);
 TInstrument=class public Name:string;Kind:TInstrumentKind;function ReadValue(const S:TSimulationSnapshot):Double;function UnitName:string;end;
 TTelemetryRecorder=class private FLines:TStringList;public constructor Create;destructor Destroy;override;procedure Sample(const S:TSimulationSnapshot);procedure SaveCSV(const FN:string);property Lines:TStringList read FLines;end;
implementation
function TInstrument.ReadValue(const S:TSimulationSnapshot):Double;begin case Kind of ikVoltmeter:Result:=S.Electrical.BusVoltage;ikAmmeter:Result:=S.Electrical.TotalCurrent;ikPowerMeter:Result:=S.Electrical.ElectricalPower;ikTachometer:Result:=S.Mechanical.Velocity;ikTorqueMeter:Result:=S.Mechanical.Torque;ikThermometer:Result:=S.Thermal.Temperature;end;end;
function TInstrument.UnitName:string;begin case Kind of ikVoltmeter:Result:='V';ikAmmeter:Result:='A';ikPowerMeter:Result:='W';ikTachometer:Result:='rad/s';ikTorqueMeter:Result:='N.m';ikThermometer:Result:='C';end;end;
constructor TTelemetryRecorder.Create;begin inherited;FLines:=TStringList.Create;FLines.Add('time_s,voltage_v,current_a,power_w,position,velocity,torque_nm,temp_c,pwm');end;destructor TTelemetryRecorder.Destroy;begin FLines.Free;inherited;end;
procedure TTelemetryRecorder.Sample(const S:TSimulationSnapshot);begin FLines.Add(Format('%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f',[S.Clock.Time,S.Electrical.BusVoltage,S.Electrical.TotalCurrent,S.Electrical.ElectricalPower,S.Mechanical.Position,S.Mechanical.Velocity,S.Mechanical.Torque,S.Thermal.Temperature,S.Control.PWM]));end;
procedure TTelemetryRecorder.SaveCSV(const FN:string);begin FLines.SaveToFile(FN);end;
end.
