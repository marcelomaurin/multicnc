program test_mechanics;
{$mode objfpc}{$H+}
uses Math,multiphysics_vector,multiphysics_mechanics;
var S:TLinearMotion;G:TVector3;F:TVector3;N:Double;
begin G:=V3(0,0,-9.80665);F:=GravityForce(10,G);if Abs(F.Z+98.0665)>0.001 then Halt(1);N:=InclineNormalForce(10,9.80665,0);if Abs(N-98.0665)>0.001 then Halt(2);if StaticFrictionLimit(N,0.5)<=KineticFriction(N,0.3)then Halt(3);S.Mass:=10;LinearMotionStep(S,100,1);if(S.Acceleration<>10)or(S.Velocity<>10)or(S.Position<>10)then Halt(4);if Abs(StoppingDistance(10,0.5,10)-10)>0.001 then Halt(5);if TractionForce(1000,10,200)>100.001 then Halt(6);Writeln('PASS gravity traction friction motion');end.
