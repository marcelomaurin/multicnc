program test_physical_devices;
{$mode objfpc}{$H+}
uses Math,multiphysics_physical_devices;
var A:TActuatorModel;M:TRotaryMotorModel;L:TLaserModel;S:TSensorModel;T:TThermistorModel;I:Double;
begin A.Resistance:=4;A.ForceConstant:=10;A.MaxForce:=100;A.Mass:=1;A.Damping:=0.1;I:=LinearActuatorStep(A,12,0,0.01);if(I<=0)or(A.Position<=0)then Halt(1);M.Resistance:=2;M.Kt:=0.1;M.Ke:=0.1;M.Inertia:=0.01;I:=RotaryMotorStep(M,12,0,0.01);if(I<=0)or(M.Speed<=0)then Halt(2);L.ForwardVoltage:=2;L.Efficiency:=0.3;L.MaxOpticalPower:=5;if LaserOpticalPower(L,12,1)<=0 then Halt(3);S.MinInput:=0;S.MaxInput:=100;S.MinOutput:=0;S.MaxOutput:=5;if Abs(SensorOutput(S,50)-2.5)>0.001 then Halt(4);T.R25:=10000;T.Beta:=3950;T.T0:=25;if Abs(NTCResistance(T,25)-10000)>1 then Halt(5);if HeaterPower(24,12)<>48 then Halt(6);if StrainGaugeResistance(120,2,0.001)<=120 then Halt(7);Writeln('PASS physical devices');end.
