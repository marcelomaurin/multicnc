unit multiphysics_components;
{$mode objfpc}{$H+}
interface
uses Math,multiphysics_runtime_types;
type
 TPowerSupply=record NominalVoltage,MaxCurrent,InternalResistance:Double;end;
 TDCMotor=record Resistance,Kt,Ke,Inertia,ViscousFriction,ThermalResistance,ThermalCapacity:Double;end;
 TAxisLoad=record Inertia,Friction,ExternalTorque:Double;end;
 TPIDController=record Kp,Ki,Kd,Integral,PreviousError:Double;end;
function Clamp(V,A,B:Double):Double;
function ControllerStep(var C:TPIDController;SetPoint,Measured,Dt:Double):Double;
procedure ElectricalMotorStep(const PSU:TPowerSupply;const Motor:TDCMotor;PWM,Omega:Double;var E:TElectricalState;out MotorCurrent,MotorTorque,LossPower:Double);
procedure MechanicalMotorStep(const Motor:TDCMotor;const Load:TAxisLoad;MotorTorque,Dt:Double;var M:TMechanicalState);
procedure ThermalMotorStep(const Motor:TDCMotor;LossPower,Dt:Double;var T:TThermalState);
implementation
function Clamp(V,A,B:Double):Double;begin if V<A then Exit(A);if V>B then Exit(B);Result:=V;end;
function ControllerStep(var C:TPIDController;SetPoint,Measured,Dt:Double):Double;var E,D:Double;begin E:=SetPoint-Measured;if Dt>0 then begin C.Integral:=C.Integral+E*Dt;D:=(E-C.PreviousError)/Dt;end else D:=0;C.PreviousError:=E;Result:=Clamp(C.Kp*E+C.Ki*C.Integral+C.Kd*D,0,1);end;
procedure ElectricalMotorStep(const PSU:TPowerSupply;const Motor:TDCMotor;PWM,Omega:Double;var E:TElectricalState;out MotorCurrent,MotorTorque,LossPower:Double);var Applied,BackEMF,I:Double;begin Applied:=Clamp(PWM,0,1)*PSU.NominalVoltage;BackEMF:=Motor.Ke*Omega;if Motor.Resistance>0 then I:=(Applied-BackEMF)/Motor.Resistance else I:=0;I:=Clamp(I,-PSU.MaxCurrent,PSU.MaxCurrent);E.SupplyVoltage:=PSU.NominalVoltage;E.TotalCurrent:=Abs(I);E.BusVoltage:=Max(0,PSU.NominalVoltage-E.TotalCurrent*PSU.InternalResistance);E.ElectricalPower:=E.BusVoltage*E.TotalCurrent;MotorCurrent:=I;MotorTorque:=Motor.Kt*I;LossPower:=I*I*Motor.Resistance;end;
procedure MechanicalMotorStep(const Motor:TDCMotor;const Load:TAxisLoad;MotorTorque,Dt:Double;var M:TMechanicalState);var J,Oppose:Double;begin J:=Motor.Inertia+Load.Inertia;if J<=0 then Exit;Oppose:=Motor.ViscousFriction*M.Velocity+Load.Friction*M.Velocity+Load.ExternalTorque;M.Torque:=MotorTorque;M.LoadTorque:=Oppose;M.Acceleration:=(MotorTorque-Oppose)/J;M.Velocity:=M.Velocity+M.Acceleration*Dt;M.Position:=M.Position+M.Velocity*Dt;end;
procedure ThermalMotorStep(const Motor:TDCMotor;LossPower,Dt:Double;var T:TThermalState);var Cooling:Double;begin T.HeatPower:=LossPower;if Motor.ThermalCapacity<=0 then Exit;if Motor.ThermalResistance>0 then Cooling:=(T.Temperature-T.AmbientTemperature)/Motor.ThermalResistance else Cooling:=0;T.Temperature:=T.Temperature+(LossPower-Cooling)*Dt/Motor.ThermalCapacity;end;
end.
