unit multiphysics_cnc_reference;
{$mode objfpc}{$H+}
interface
uses multiphysics_graph,multiphysics_component_library;
function BuildReferenceCNC:TSimulationGraph;
implementation
function BuildReferenceCNC:TSimulationGraph;var G:TSimulationGraph;C:TSimComponent;begin G:=TSimulationGraph.Create;G.AddComponent(NewPowerSupply('PSU_24V',24,15));G.AddComponent(NewController('CTRL_CNC'));G.AddComponent(NewPWMDriver('DRV_X'));G.AddComponent(NewDCMotor('MOTOR_X'));G.AddComponent(NewAxisLoad('SCREW_X'));G.AddComponent(NewSpeedSensor('ENC_X'));C:=TSimComponent.Create('LIMIT_X','Fim de curso X',ckSpeedSensor,cdSensor);C.AddPort('OUT',ptSignal);G.AddComponent(C);G.Connect('PSU_24V','V+','DRV_X','VIN',ptElectrical);G.Connect('CTRL_CNC','PWM','DRV_X','CMD',ptSignal);G.Connect('DRV_X','VOUT','MOTOR_X','PWR',ptElectrical);G.Connect('MOTOR_X','SHAFT','SCREW_X','SHAFT',ptMechanicalRotary);G.Connect('MOTOR_X','SHAFT','ENC_X','SHAFT',ptMechanicalRotary);G.Connect('ENC_X','OUT','CTRL_CNC','SENSOR',ptSignal);Result:=G;end;
end.
