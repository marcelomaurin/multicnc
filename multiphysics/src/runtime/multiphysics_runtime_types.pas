unit multiphysics_runtime_types;
{$mode objfpc}{$H+}
interface
type
 TSimulationState=(simStopped,simRunning,simPaused,simFault);
 TSimulationClock=record Time,Dt:Double;Step:Int64;State:TSimulationState;end;
 TElectricalState=record SupplyVoltage,BusVoltage,TotalCurrent,ElectricalPower:Double;end;
 TMechanicalState=record Position,Velocity,Acceleration,Torque,LoadTorque:Double;end;
 TThermalState=record Temperature,AmbientTemperature,HeatPower:Double;end;
 TControlState=record PWM:Double;SensorValue,SetPoint:Double;Enabled:Boolean;end;
 TSimulationSnapshot=record Clock:TSimulationClock;Electrical:TElectricalState;Mechanical:TMechanicalState;Thermal:TThermalState;Control:TControlState;end;
implementation end.
