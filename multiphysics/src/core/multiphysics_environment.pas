unit multiphysics_environment;
{$mode objfpc}{$H+}
interface
uses Math,multiphysics_types;
type
 TEnvironmentPreset=(epAir,epWater,epVacuum,epCustom);
 TEnvironmentModel=record
  Preset:TEnvironmentPreset;Name:string;
  Temperature,Pressure,Density,DynamicViscosity:Double;
  GravityX,GravityY,GravityZ:Double;
  FlowX,FlowY,FlowZ:Double;
 end;
 TFluidEstimate=record Speed,DynamicPressure,DragForce,BuoyancyForce:Double;end;
function AirEnvironment:TEnvironmentModel;
function WaterEnvironment:TEnvironmentModel;
function VacuumEnvironment:TEnvironmentModel;
function FlowSpeed(const E:TEnvironmentModel):Double;
function EstimateFluidLoads(const E:TEnvironmentModel;ReferenceArea,DragCoefficient,DisplacedVolume:Double):TFluidEstimate;
implementation
function Base(const N:string;P:TEnvironmentPreset):TEnvironmentModel;begin FillChar(Result,SizeOf(Result),0);Result.Preset:=P;Result.Name:=N;Result.GravityZ:=-9.80665;end;
function AirEnvironment:TEnvironmentModel;begin Result:=Base('Ar',epAir);Result.Temperature:=20;Result.Pressure:=101325;Result.Density:=1.204;Result.DynamicViscosity:=1.825e-5;end;
function WaterEnvironment:TEnvironmentModel;begin Result:=Base('Agua',epWater);Result.Temperature:=20;Result.Pressure:=101325;Result.Density:=998.2;Result.DynamicViscosity:=1.002e-3;end;
function VacuumEnvironment:TEnvironmentModel;begin Result:=Base('Vacuo',epVacuum);Result.Temperature:=20;Result.Pressure:=0;Result.Density:=0;Result.DynamicViscosity:=0;end;
function FlowSpeed(const E:TEnvironmentModel):Double;begin Result:=Sqrt(Sqr(E.FlowX)+Sqr(E.FlowY)+Sqr(E.FlowZ));end;
function EstimateFluidLoads(const E:TEnvironmentModel;ReferenceArea,DragCoefficient,DisplacedVolume:Double):TFluidEstimate;var V,G:Double;begin FillChar(Result,SizeOf(Result),0);V:=FlowSpeed(E);G:=Sqrt(Sqr(E.GravityX)+Sqr(E.GravityY)+Sqr(E.GravityZ));Result.Speed:=V;Result.DynamicPressure:=0.5*E.Density*Sqr(V);Result.DragForce:=Result.DynamicPressure*DragCoefficient*ReferenceArea;Result.BuoyancyForce:=E.Density*G*DisplacedVolume;end;
end.
