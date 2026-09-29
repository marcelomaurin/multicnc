unit multiphysics_coupling;
{$mode objfpc}{$H+}
interface
uses multiphysics_runtime_types;
type TFieldLoads=record Torque,Force,Heat,Temperature,Velocity:Double;end;
function RuntimeToFieldLoads(const S:TSimulationSnapshot):TFieldLoads;
implementation
function RuntimeToFieldLoads(const S:TSimulationSnapshot):TFieldLoads;begin Result.Torque:=S.Mechanical.Torque;Result.Force:=0;Result.Heat:=S.Thermal.HeatPower;Result.Temperature:=S.Thermal.Temperature;Result.Velocity:=S.Mechanical.Velocity;end;
end.
