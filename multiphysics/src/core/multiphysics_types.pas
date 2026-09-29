unit multiphysics_types;
{$mode objfpc}{$H+}
interface
type
 TPhysicsKind=(pkStructural,pkThermal,pkModal,pkDynamic,pkFriction,pkFluidDrag);
 TMaterialClass=(mcMetal,mcPolymer,mcElastomer,mcCeramic,mcGlass,mcComposite,mcSemiconductor,mcWood,mcOther);
 TMaterial=record Name:string;MaterialClass:TMaterialClass;Density,YoungModulus,Poisson,ThermalConductivity,SpecificHeat,ThermalExpansion,YieldStrength,ElectricalResistivity,Emissivity,MaxServiceTemperature,MeltingTemperature:Double;end;
 TBoundaryKind=(bkFixed,bkForce,bkPressure,bkTemperature,bkHeatFlux,bkConvection,bkGravity,bkAcceleration,bkVelocity);
 TBoundaryCondition=record Name,TargetID:string;Kind:TBoundaryKind;X,Y,Z,Value:Double;end;
 TContact=record Name,PartA,PartB:string;FrictionCoefficient,ThermalConductance:Double;end;
 TEnvironment=record AmbientTemperature,GravityX,GravityY,GravityZ,FluidDensity,FluidViscosity,FlowX,FlowY,FlowZ,DragCoefficient:Double;end;
 TAnalysisSettings=record Physics:set of TPhysicsKind;MeshSize,TimeStep,TotalTime:Double;Modes:Integer;NonLinear:Boolean;end;
 TPhysicsResult=record Solved:Boolean;MaxDisplacement,MaxVonMises,MaxTemperature,MinTemperature,MaxStrain,MaxContactPressure,FundamentalFrequency,MaxDragForce:Double;Message:string;end;
implementation
end.
