program test_buoyancy;
{$mode objfpc}{$H+}
uses Math,multiphysics_vector,multiphysics_rigidbody,multiphysics_environment,multiphysics_buoyancy;
var B:TRigidBodyState;E:TEnvironmentModel;R:TBuoyancyResult;
begin FillChar(B,SizeOf(B),0);B.Mass:=100;B.CenterOfMass:=V3(0,0,0.2);E:=WaterEnvironment;R:=EvaluateBuoyancy(B,E,0.2,V3(0.1,0,0));if R.State<>fsFloats then Halt(1);if R.Buoyancy<=R.Weight then Halt(2);if Abs(R.Moment.Y)<1e-6 then Halt(3);R:=EvaluateBuoyancy(B,E,0.05,V3(0,0,0));if R.State<>fsSinks then Halt(4);Writeln('PASS buoyancy');end.
