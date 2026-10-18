unit multiphysics_types;
{$mode objfpc}{$H+}
interface
type
 TPhysicsKind=(pkStructural,pkThermal,pkModal,pkDynamic,pkFriction,pkFluidDrag,pkMagnetic,pkElectromagnetic);
 TMaterialClass=(mcMetal,mcPolymer,mcElastomer,mcCeramic,mcGlass,mcComposite,mcSemiconductor,mcWood,mcLiquid,mcGas,mcFuel,mcChemical,mcOther);
 TEnergySourceKind=(eskBattery,eskSolarPanel,eskFuel,eskExternal);
 TChemicalHazard=(chNone,chFlammable,chCorrosive,chToxic,chOxidizing,chCompressedGas);
 TMaterial=record Name:string;MaterialClass:TMaterialClass;Density,YoungModulus,Poisson,ThermalConductivity,SpecificHeat,ThermalExpansion,YieldStrength,ElectricalResistivity,RelativePermeability,Emissivity,MaxServiceTemperature,MeltingTemperature:Double;end;
 { novos no fim: o ordinal e gravado no .mphys }
 TBoundaryKind=(bkFixed,bkForce,bkPressure,bkTemperature,bkHeatFlux,bkConvection,bkGravity,bkAcceleration,bkVelocity,bkDisplacement,bkHeatPower);
 { TargetID = peca; TargetFace = 'PECA/primitiva/face', 'PECA/face' (todas as
   primitivas) ou vazio (todas as faces da peca). Unidades SI: N, Pa, m, C,
   W/m2, W/m2K, W. Value2 = temperatura ambiente na conveccao. DofMask: bits
   0..2 = x, y, z fixos (0 = todos). }
 TBoundaryCondition=record Name,TargetID:string;Kind:TBoundaryKind;X,Y,Z,Value:Double;TargetFace:string;Value2:Double;DofMask:Integer;end;
 TContact=record Name,PartA,PartB:string;FrictionCoefficient,StaticFrictionCoefficient,RollingFrictionCoefficient,ThermalConductance:Double;end;
 TEnvironment=record AmbientTemperature,GravityX,GravityY,GravityZ,FluidDensity,FluidViscosity,FlowX,FlowY,FlowZ,DragCoefficient:Double;end;
 { MeshSize em metros. Quadratic = TET10. Solver: 0 = proprio, 1 = CalculiX. }
 TAnalysisSettings=record Physics:set of TPhysicsKind;MeshSize,TimeStep,TotalTime:Double;Modes:Integer;NonLinear:Boolean;Quadratic,CheckConvergence:Boolean;Solver:Integer;end;
 TPhysicsResult=record Solved:Boolean;MaxDisplacement,MaxVonMises,MaxTemperature,MinTemperature,MaxStrain,MaxContactPressure,FundamentalFrequency,MaxDragForce:Double;Message:string;Fidelity:string;MeshNodes,MeshElements:Integer;SolverName:string;end;
function BoundaryKindName(K:TBoundaryKind):string;

implementation

function BoundaryKindName(K:TBoundaryKind):string;
begin
  case K of
    bkFixed: Result:='Fixacao';
    bkForce: Result:='Forca';
    bkPressure: Result:='Pressao';
    bkTemperature: Result:='Temperatura';
    bkHeatFlux: Result:='Fluxo de calor';
    bkConvection: Result:='Conveccao';
    bkGravity: Result:='Gravidade';
    bkAcceleration: Result:='Aceleracao';
    bkVelocity: Result:='Velocidade';
    bkDisplacement: Result:='Deslocamento prescrito';
    bkHeatPower: Result:='Potencia dissipada';
    else Result:='?';
  end;
end;
end.
