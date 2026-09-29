program test_digital_power;
{$mode objfpc}{$H+}
uses Math,multiphysics_digital_power;
var F:TFlipFlop;T:TTimer555;S:TStepperDriverState;P:TSwitchPower;C:LongWord;V:Double;
begin if not LogicEval(lgAND,True,True)then Halt(1);if LogicEval(lgXOR,True,True)then Halt(2);FlipFlopDStep(F,True,True);if not F.Q then Halt(3);T.R1:=1000;T.R2:=1000;T.C:=0.000001;if Timer555Frequency(T)<400 then Halt(4);C:=ADCConvert(2.5,5,10);if Abs(Integer(C)-512)>1 then Halt(5);V:=DACConvert(512,5,10);if Abs(V-2.502)>0.02 then Halt(6);if Abs(BuckOutput(24,0.5,0.9)-10.8)>0.001 then Halt(7);if BoostOutput(12,0.5,0.9)<21 then Halt(8);if HBridgeVoltage(24,0.5,False)>=0 then Halt(9);StepperDriverStep(S,True,True,True);StepperDriverStep(S,False,True,True);StepperDriverStep(S,True,True,True);if S.StepCount<>2 then Halt(10);P.OnResistance:=0.05;P.Threshold:=5;if Abs(PowerSwitchCurrent(P,10,1)-20)>0.001 then Halt(11);Writeln('PASS digital and power electronics');end.
