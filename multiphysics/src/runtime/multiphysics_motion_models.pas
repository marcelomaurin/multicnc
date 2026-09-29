unit multiphysics_motion_models;
{$mode objfpc}{$H+}
interface
uses Math;
type
 TStepperModel=record StepsPerRev,Microsteps,MaxTorque,Inertia,Angle,Velocity:Double;end;
 TServoModel=record Position,Target,MaxSpeed,Kp:Double;end;
 TBLDCModel=record Kt,Ke,Resistance,Inertia,Velocity:Double;end;
 TGearModel=record Ratio,Efficiency:Double;end;
 TLeadScrewModel=record PitchMM,Efficiency:Double;end;
 TSpringDamperModel=record K,C,RestPosition:Double;end;
procedure StepperPulse(var M:TStepperModel;Direction:Integer);
procedure ServoStep(var S:TServoModel;Dt:Double);
function BLDCStep(var M:TBLDCModel;Voltage,LoadTorque,Dt:Double):Double;
function GearOutputTorque(const G:TGearModel;InputTorque:Double):Double;
function GearOutputSpeed(const G:TGearModel;InputSpeed:Double):Double;
function ScrewLinearPosition(const S:TLeadScrewModel;AngleRad:Double):Double;
function SpringDamperForce(const S:TSpringDamperModel;Position,Velocity:Double):Double;
implementation
procedure StepperPulse(var M:TStepperModel;Direction:Integer);var N:Double;begin N:=M.StepsPerRev*Max(1,M.Microsteps);if N>0 then M.Angle:=M.Angle+Direction*2*Pi/N;end;
procedure ServoStep(var S:TServoModel;Dt:Double);var V:Double;begin V:=(S.Target-S.Position)*S.Kp;V:=Max(-S.MaxSpeed,Min(S.MaxSpeed,V));S.Position:=S.Position+V*Dt;end;
function BLDCStep(var M:TBLDCModel;Voltage,LoadTorque,Dt:Double):Double;var I,T,A:Double;begin if M.Resistance<=0 then Exit(0);I:=(Voltage-M.Ke*M.Velocity)/M.Resistance;T:=M.Kt*I;if M.Inertia>0 then begin A:=(T-LoadTorque)/M.Inertia;M.Velocity:=M.Velocity+A*Dt;end;Result:=I;end;
function GearOutputTorque(const G:TGearModel;InputTorque:Double):Double;begin Result:=InputTorque*G.Ratio*G.Efficiency;end;
function GearOutputSpeed(const G:TGearModel;InputSpeed:Double):Double;begin if G.Ratio<>0 then Result:=InputSpeed/G.Ratio else Result:=0;end;
function ScrewLinearPosition(const S:TLeadScrewModel;AngleRad:Double):Double;begin Result:=(AngleRad/(2*Pi))*S.PitchMM;end;
function SpringDamperForce(const S:TSpringDamperModel;Position,Velocity:Double):Double;begin Result:=-S.K*(Position-S.RestPosition)-S.C*Velocity;end;
end.
