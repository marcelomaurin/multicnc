unit multiphysics_rigidbody;
{$mode objfpc}{$H+}
interface
uses multiphysics_vector;
type
 TRigidBodyState=record Mass:Double;CenterOfMass,Position,Velocity,Angles,AngularVelocity:TVector3;Inertia:TVector3;end;
 TForceMoment=record Force,Moment:TVector3;end;
 TAcceleration6DOF=record Linear,Angular:TVector3;end;
function ForceAtPoint(const Force,Point,Center:TVector3):TForceMoment;
function SolveAcceleration(const Body:TRigidBodyState;const Load:TForceMoment):TAcceleration6DOF;
procedure IntegrateEuler(var Body:TRigidBodyState;const A:TAcceleration6DOF;Dt:Double);
implementation
function ForceAtPoint(const Force,Point,Center:TVector3):TForceMoment;begin Result.Force:=Force;Result.Moment:=VCross(VSub(Point,Center),Force);end;
function SolveAcceleration(const Body:TRigidBodyState;const Load:TForceMoment):TAcceleration6DOF;begin Result.Linear:=V3(0,0,0);Result.Angular:=V3(0,0,0);if Body.Mass>0 then Result.Linear:=VScale(Load.Force,1/Body.Mass);if Body.Inertia.X>0 then Result.Angular.X:=Load.Moment.X/Body.Inertia.X;if Body.Inertia.Y>0 then Result.Angular.Y:=Load.Moment.Y/Body.Inertia.Y;if Body.Inertia.Z>0 then Result.Angular.Z:=Load.Moment.Z/Body.Inertia.Z;end;
procedure IntegrateEuler(var Body:TRigidBodyState;const A:TAcceleration6DOF;Dt:Double);begin Body.Velocity:=VAdd(Body.Velocity,VScale(A.Linear,Dt));Body.Position:=VAdd(Body.Position,VScale(Body.Velocity,Dt));Body.AngularVelocity:=VAdd(Body.AngularVelocity,VScale(A.Angular,Dt));Body.Angles:=VAdd(Body.Angles,VScale(Body.AngularVelocity,Dt));end;
end.
