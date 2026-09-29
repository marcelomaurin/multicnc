unit multiphysics_cnc_stepper;
{$mode objfpc}{$H+}
interface
uses multiphysics_graph,multiphysics_component_library;
function BuildStepperCNC:TSimulationGraph;
implementation
function BuildStepperCNC:TSimulationGraph;var G:TSimulationGraph;begin G:=TSimulationGraph.Create;G.AddComponent(NewPowerSupply('PSU_24V',24,15));G.AddComponent(NewController('CTRL_CNC'));G.AddComponent(NewPWMDriver('DRV_X'));G.AddComponent(NewStepper('MOTOR_X'));G.AddComponent(NewLeadScrew('SCREW_X',5));G.AddComponent(NewEndStop('LIMIT_X'));G.Connect('PSU_24V','V+','DRV_X','VIN',ptElectrical);G.Connect('CTRL_CNC','PWM','DRV_X','CMD',ptSignal);G.Connect('DRV_X','VOUT','MOTOR_X','PWR',ptElectrical);G.Connect('MOTOR_X','SHAFT','SCREW_X','SHAFT',ptMechanicalRotary);Result:=G;end;
end.
