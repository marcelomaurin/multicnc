unit multiphysics_mechanics;
{$mode objfpc}{$H+}
interface
uses Math,multiphysics_vector,multiphysics_rigidbody;
type
 TFrictionModel=record StaticCoefficient,KineticCoefficient,RollingCoefficient:Double;end;
 TLinearMotion=record Position,Velocity,Acceleration,Mass:Double;end;
function GravityForce(Mass:Double;const Gravity:TVector3):TVector3;
function Weight(Mass,Gravity:Double):Double;
function KineticEnergy(Mass,Velocity:Double):Double;
function Momentum(Mass,Velocity:Double):Double;
function TractionForce(Power,Velocity,MaxForce:Double):Double;
function StaticFrictionLimit(NormalForce,MuStatic:Double):Double;
function KineticFriction(NormalForce,MuKinetic:Double):Double;
function RollingResistance(NormalForce,MuRolling:Double):Double;
function InclineNormalForce(Mass,Gravity,AngleRad:Double):Double;
function InclineGravityForce(Mass,Gravity,AngleRad:Double):Double;
function NetLinearForce(DriveForce,OpposingForce,FrictionForce:Double):Double;
procedure LinearMotionStep(var S:TLinearMotion;NetForce,Dt:Double);
function StoppingDistance(Velocity,Mu,Gravity:Double):Double;
implementation
function GravityForce(Mass:Double;const Gravity:TVector3):TVector3;begin Result:=VScale(Gravity,Mass);end;
function Weight(Mass,Gravity:Double):Double;begin Result:=Mass*Abs(Gravity);end;
function KineticEnergy(Mass,Velocity:Double):Double;begin Result:=0.5*Mass*Sqr(Velocity);end;
function Momentum(Mass,Velocity:Double):Double;begin Result:=Mass*Velocity;end;
function TractionForce(Power,Velocity,MaxForce:Double):Double;begin if Abs(Velocity)<1e-6 then Result:=MaxForce else Result:=Min(MaxForce,Abs(Power/Velocity));if Power<0 then Result:=-Result;end;
function StaticFrictionLimit(NormalForce,MuStatic:Double):Double;begin Result:=Abs(NormalForce)*Max(0,MuStatic);end;
function KineticFriction(NormalForce,MuKinetic:Double):Double;begin Result:=Abs(NormalForce)*Max(0,MuKinetic);end;
function RollingResistance(NormalForce,MuRolling:Double):Double;begin Result:=Abs(NormalForce)*Max(0,MuRolling);end;
function InclineNormalForce(Mass,Gravity,AngleRad:Double):Double;begin Result:=Mass*Abs(Gravity)*Cos(AngleRad);end;
function InclineGravityForce(Mass,Gravity,AngleRad:Double):Double;begin Result:=Mass*Abs(Gravity)*Sin(AngleRad);end;
function NetLinearForce(DriveForce,OpposingForce,FrictionForce:Double):Double;begin Result:=DriveForce-OpposingForce-FrictionForce;end;
procedure LinearMotionStep(var S:TLinearMotion;NetForce,Dt:Double);begin if(S.Mass<=0)or(Dt<=0)then Exit;S.Acceleration:=NetForce/S.Mass;S.Velocity:=S.Velocity+S.Acceleration*Dt;S.Position:=S.Position+S.Velocity*Dt;end;
function StoppingDistance(Velocity,Mu,Gravity:Double):Double;begin if(Mu<=0)or(Gravity=0)then Exit(Infinity);Result:=Sqr(Velocity)/(2*Mu*Abs(Gravity));end;
end.
