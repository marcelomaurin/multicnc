unit multiphysics_runtime;
{$mode objfpc}{$H+}
interface
uses multiphysics_runtime_types,multiphysics_components;
type
 TSimulationRuntime=class
 private FPSU:TPowerSupply;FMotor:TDCMotor;FLoad:TAxisLoad;FController:TPIDController;FS:TSimulationSnapshot;
 public constructor Create;procedure Reset;procedure Start;procedure Pause;procedure Stop;procedure Step;property Snapshot:TSimulationSnapshot read FS;property PSU:TPowerSupply read FPSU write FPSU;property Motor:TDCMotor read FMotor write FMotor;property Load:TAxisLoad read FLoad write FLoad;property Controller:TPIDController read FController write FController;
 end;
implementation
constructor TSimulationRuntime.Create;begin inherited;FPSU.NominalVoltage:=24;FPSU.MaxCurrent:=10;FPSU.InternalResistance:=0.05;FMotor.Resistance:=2;FMotor.Kt:=0.08;FMotor.Ke:=0.08;FMotor.Inertia:=0.002;FMotor.ViscousFriction:=0.001;FMotor.ThermalResistance:=2;FMotor.ThermalCapacity:=100;FLoad.Inertia:=0.01;FLoad.Friction:=0.002;FController.Kp:=0.02;Reset;end;
procedure TSimulationRuntime.Reset;begin FillChar(FS,SizeOf(FS),0);FS.Clock.Dt:=0.01;FS.Clock.State:=simStopped;FS.Thermal.AmbientTemperature:=20;FS.Thermal.Temperature:=20;FS.Control.SetPoint:=100;FS.Control.Enabled:=True;end;
procedure TSimulationRuntime.Start;begin FS.Clock.State:=simRunning;end;procedure TSimulationRuntime.Pause;begin if FS.Clock.State=simRunning then FS.Clock.State:=simPaused;end;procedure TSimulationRuntime.Stop;begin FS.Clock.State:=simStopped;FS.Control.PWM:=0;end;
procedure TSimulationRuntime.Step;var I,Torque,Loss:Double;begin if FS.Clock.State<>simRunning then Exit;if FS.Control.Enabled then FS.Control.PWM:=ControllerStep(FController,FS.Control.SetPoint,FS.Mechanical.Velocity,FS.Clock.Dt)else FS.Control.PWM:=0;ElectricalMotorStep(FPSU,FMotor,FS.Control.PWM,FS.Mechanical.Velocity,FS.Electrical,I,Torque,Loss);MechanicalMotorStep(FMotor,FLoad,Torque,FS.Clock.Dt,FS.Mechanical);ThermalMotorStep(FMotor,Loss,FS.Clock.Dt,FS.Thermal);FS.Control.SensorValue:=FS.Mechanical.Velocity;FS.Clock.Time:=FS.Clock.Time+FS.Clock.Dt;Inc(FS.Clock.Step);end;
end.
