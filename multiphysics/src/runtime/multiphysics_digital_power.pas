unit multiphysics_digital_power;
{$mode objfpc}{$H+}
interface
uses Math;
type TLogicGate=(lgAND,lgOR,lgNOT,lgNAND,lgNOR,lgXOR);
 TFlipFlop=record Q,LastClock:Boolean;end;
 TTimer555=record R1,R2,C,Phase:Double;Output:Boolean;end;
 TSwitchPower=record OnResistance,Threshold:Double;Latched:Boolean;end;
 TStepperDriverState=record Enabled,Direction,LastStep:Boolean;StepCount:Int64;CurrentLimit:Double;end;
function LogicEval(G:TLogicGate;A,B:Boolean):Boolean;
procedure FlipFlopDStep(var F:TFlipFlop;D,Clock:Boolean);
function Timer555Frequency(const T:TTimer555):Double;
procedure Timer555Step(var T:TTimer555;Dt:Double);
function ADCConvert(V,VRef:Double;Bits:Integer):LongWord;
function DACConvert(Code:LongWord;VRef:Double;Bits:Integer):Double;
function OptoOutput(InputCurrent,CTR:Double):Double;
function BuckOutput(Vin,Duty,Efficiency:Double):Double;
function BoostOutput(Vin,Duty,Efficiency:Double):Double;
function HBridgeVoltage(Vbus,Duty:Double;Direction:Boolean):Double;
function PowerSwitchCurrent(const S:TSwitchPower;Control,Voltage:Double):Double;
procedure StepperDriverStep(var S:TStepperDriverState;StepSignal,Dir,Enable:Boolean);
implementation
function LogicEval(G:TLogicGate;A,B:Boolean):Boolean;begin case G of lgAND:Result:=A and B;lgOR:Result:=A or B;lgNOT:Result:=not A;lgNAND:Result:=not(A and B);lgNOR:Result:=not(A or B);lgXOR:Result:=A xor B;end;end;
procedure FlipFlopDStep(var F:TFlipFlop;D,Clock:Boolean);begin if Clock and not F.LastClock then F.Q:=D;F.LastClock:=Clock;end;
function Timer555Frequency(const T:TTimer555):Double;begin if(T.C>0)and((T.R1+2*T.R2)>0)then Result:=1.44/((T.R1+2*T.R2)*T.C)else Result:=0;end;
procedure Timer555Step(var T:TTimer555;Dt:Double);var F:Double;begin F:=Timer555Frequency(T);T.Phase:=T.Phase+Dt*F;if T.Phase>=1 then T.Phase:=T.Phase-Floor(T.Phase);T.Output:=T.Phase<0.5;end;
function ADCConvert(V,VRef:Double;Bits:Integer):LongWord;var M:QWord;begin if(Bits<1)or(Bits>31)or(VRef<=0)then Exit(0);M:=(QWord(1) shl Bits)-1;Result:=Round(Max(0,Min(VRef,V))/VRef*M);end;
function DACConvert(Code:LongWord;VRef:Double;Bits:Integer):Double;var M:QWord;begin if(Bits<1)or(Bits>31)then Exit(0);M:=(QWord(1) shl Bits)-1;Result:=Min(QWord(Code),M)/M*VRef;end;
function OptoOutput(InputCurrent,CTR:Double):Double;begin Result:=Max(0,InputCurrent*CTR);end;
function BuckOutput(Vin,Duty,Efficiency:Double):Double;begin Result:=Max(0,Vin*Max(0,Min(1,Duty))*Efficiency);end;
function BoostOutput(Vin,Duty,Efficiency:Double):Double;begin Duty:=Max(0,Min(0.95,Duty));Result:=Max(0,Vin/(1-Duty)*Efficiency);end;
function HBridgeVoltage(Vbus,Duty:Double;Direction:Boolean):Double;begin Result:=Vbus*Max(0,Min(1,Duty));if not Direction then Result:=-Result;end;
function PowerSwitchCurrent(const S:TSwitchPower;Control,Voltage:Double):Double;begin if(Control>=S.Threshold)and(S.OnResistance>0)then Result:=Voltage/S.OnResistance else Result:=0;end;
procedure StepperDriverStep(var S:TStepperDriverState;StepSignal,Dir,Enable:Boolean);begin S.Enabled:=Enable;S.Direction:=Dir;if Enable and StepSignal and not S.LastStep then if Dir then Inc(S.StepCount)else Dec(S.StepCount);S.LastStep:=StepSignal;end;
end.
