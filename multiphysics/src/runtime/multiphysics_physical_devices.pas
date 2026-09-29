unit multiphysics_physical_devices;
{$mode objfpc}{$H+}
interface
uses Math;
type
 TActuatorModel=record Resistance,ForceConstant,MaxForce,Position,Velocity,Mass,Damping:Double;end;
 TRotaryMotorModel=record Resistance,Kt,Ke,Inertia,Friction,Speed,Torque:Double;end;
 TLaserModel=record ForwardVoltage,Efficiency,MaxOpticalPower,Temperature:Double;end;
 TSensorModel=record MinInput,MaxInput,MinOutput,MaxOutput,Noise,Value:Double;end;
 TThermistorModel=record R25,Beta,T0:Double;end;
function LinearActuatorStep(var A:TActuatorModel;Voltage,LoadForce,Dt:Double):Double;
function RotaryMotorStep(var M:TRotaryMotorModel;Voltage,LoadTorque,Dt:Double):Double;
function LaserOpticalPower(const L:TLaserModel;Voltage,Current:Double):Double;
function SensorOutput(var S:TSensorModel;PhysicalValue:Double):Double;
function NTCResistance(const T:TThermistorModel;TemperatureC:Double):Double;
function PTCResistance(R0,Alpha,TemperatureC,ReferenceC:Double):Double;
function LDRResistance(Lux,DarkResistance,LightResistance:Double):Double;
function StrainGaugeResistance(R0,GaugeFactor,Strain:Double):Double;
function HeaterPower(Voltage,Resistance:Double):Double;
implementation
function LinearActuatorStep(var A:TActuatorModel;Voltage,LoadForce,Dt:Double):Double;var I,F,Acc:Double;begin if(A.Resistance<=0)or(A.Mass<=0)then Exit(0);I:=Voltage/A.Resistance;F:=Max(-A.MaxForce,Min(A.MaxForce,A.ForceConstant*I));Acc:=(F-LoadForce-A.Damping*A.Velocity)/A.Mass;A.Velocity:=A.Velocity+Acc*Dt;A.Position:=A.Position+A.Velocity*Dt;Result:=I;end;
function RotaryMotorStep(var M:TRotaryMotorModel;Voltage,LoadTorque,Dt:Double):Double;var I,A:Double;begin if(M.Resistance<=0)or(M.Inertia<=0)then Exit(0);I:=(Voltage-M.Ke*M.Speed)/M.Resistance;M.Torque:=M.Kt*I;A:=(M.Torque-LoadTorque-M.Friction*M.Speed)/M.Inertia;M.Speed:=M.Speed+A*Dt;Result:=I;end;
function LaserOpticalPower(const L:TLaserModel;Voltage,Current:Double):Double;begin if Voltage<L.ForwardVoltage then Exit(0);Result:=Min(L.MaxOpticalPower,Max(0,(Voltage*Current)*L.Efficiency));end;
function SensorOutput(var S:TSensorModel;PhysicalValue:Double):Double;var X:Double;begin if S.MaxInput=S.MinInput then Exit(S.MinOutput);X:=(PhysicalValue-S.MinInput)/(S.MaxInput-S.MinInput);X:=Max(0,Min(1,X));S.Value:=S.MinOutput+X*(S.MaxOutput-S.MinOutput);Result:=S.Value;end;
function NTCResistance(const T:TThermistorModel;TemperatureC:Double):Double;var K,K0:Double;begin K:=TemperatureC+273.15;K0:=T.T0+273.15;if(K<=0)or(K0<=0)then Exit(0);Result:=T.R25*Exp(T.Beta*(1/K-1/K0));end;
function PTCResistance(R0,Alpha,TemperatureC,ReferenceC:Double):Double;begin Result:=R0*(1+Alpha*(TemperatureC-ReferenceC));end;
function LDRResistance(Lux,DarkResistance,LightResistance:Double):Double;begin if Lux<=0 then Exit(DarkResistance);Result:=Max(LightResistance,DarkResistance/(1+Lux));end;
function StrainGaugeResistance(R0,GaugeFactor,Strain:Double):Double;begin Result:=R0*(1+GaugeFactor*Strain);end;
function HeaterPower(Voltage,Resistance:Double):Double;begin if Resistance>0 then Result:=Sqr(Voltage)/Resistance else Result:=0;end;
end.
