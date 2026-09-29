program test_environment;
{$mode objfpc}{$H+}
uses Math,multiphysics_environment;
var E:TEnvironmentModel;R:TFluidEstimate;
begin E:=WaterEnvironment;E.FlowX:=2;R:=EstimateFluidLoads(E,1,1,0.1);if Abs(R.Speed-2)>1e-9 then Halt(1);if R.DragForce<=0 then Halt(2);if R.BuoyancyForce<=900 then Halt(3);E:=VacuumEnvironment;E.FlowX:=100;R:=EstimateFluidLoads(E,10,1,1);if R.DragForce<>0 then Halt(4);Writeln('PASS environment');end.
