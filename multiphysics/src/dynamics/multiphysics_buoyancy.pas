unit multiphysics_buoyancy;
{$mode objfpc}{$H+}
interface
uses Math,multiphysics_vector,multiphysics_rigidbody,multiphysics_environment;
type
 TFloatState=(fsInvalid,fsSinks,fsNeutral,fsFloats);
 TBuoyancyResult=record State:TFloatState;Weight,Buoyancy,NetVerticalForce:Double;CenterOfBuoyancy:TVector3;Moment:TVector3;end;
function EvaluateBuoyancy(const Body:TRigidBodyState;const Env:TEnvironmentModel;DisplacedVolume:Double;const CenterOfBuoyancy:TVector3):TBuoyancyResult;
function FloatStateName(S:TFloatState):string;
implementation
function EvaluateBuoyancy(const Body:TRigidBodyState;const Env:TEnvironmentModel;DisplacedVolume:Double;const CenterOfBuoyancy:TVector3):TBuoyancyResult;var G:Double;F:TVector3;L:TForceMoment;begin FillChar(Result,SizeOf(Result),0);Result.CenterOfBuoyancy:=CenterOfBuoyancy;G:=Sqrt(Sqr(Env.GravityX)+Sqr(Env.GravityY)+Sqr(Env.GravityZ));if (Body.Mass<=0)or(DisplacedVolume<0)then begin Result.State:=fsInvalid;Exit;end;Result.Weight:=Body.Mass*G;Result.Buoyancy:=Env.Density*G*DisplacedVolume;Result.NetVerticalForce:=Result.Buoyancy-Result.Weight;if Abs(Result.NetVerticalForce)<1e-6 then Result.State:=fsNeutral else if Result.NetVerticalForce>0 then Result.State:=fsFloats else Result.State:=fsSinks;F:=V3(0,0,Result.Buoyancy);L:=ForceAtPoint(F,CenterOfBuoyancy,Body.CenterOfMass);Result.Moment:=L.Moment;end;
function FloatStateName(S:TFloatState):string;begin case S of fsInvalid:Result:='INVALIDO';fsSinks:Result:='AFUNDA';fsNeutral:Result:='NEUTRO';fsFloats:Result:='EMPURRA PARA CIMA';end;end;
end.
