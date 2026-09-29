program test_rigidbody;
{$mode objfpc}{$H+}
uses Math,multiphysics_vector,multiphysics_rigidbody;
var B:TRigidBodyState;L:TForceMoment;A:TAcceleration6DOF;
begin FillChar(B,SizeOf(B),0);B.Mass:=10;B.Inertia:=V3(2,4,5);B.CenterOfMass:=V3(0,0,0);L:=ForceAtPoint(V3(0,0,100),V3(1,0,0),B.CenterOfMass);if Abs(L.Moment.Y+100)>1e-9 then Halt(1);A:=SolveAcceleration(B,L);if Abs(A.Linear.Z-10)>1e-9 then Halt(2);if Abs(A.Angular.Y+25)>1e-9 then Halt(3);IntegrateEuler(B,A,0.1);if B.Velocity.Z<=0 then Halt(4);Writeln('PASS rigidbody 6DOF');end.
