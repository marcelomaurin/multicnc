unit multiphysics_electromagnetics;
{$mode objfpc}{$H+}
interface
uses Math;
const MU0=4*Pi*1e-7;
type
 TMagneticField=record Bx,By,Bz,Hx,Hy,Hz:Double;end;
 TCoilModel=record Turns:Integer;Length,Area,RelativePermeability,Resistance,Inductance,Current,Flux,FluxLinkage:Double;end;
 TMagneticCore=record RelativePermeability,Area,Length,SaturationTesla:Double;end;
 TMutualInductor=record L1,L2,Coupling,MutualInductance:Double;end;
function SolenoidField(const C:TCoilModel):Double;
function MagneticFlux(B,Area:Double):Double;
function CoilInductance(const C:TCoilModel):Double;
function FaradayEMF(Turns:Integer;FluxNow,FluxPrevious,Dt:Double):Double;
function MagneticForce(B,Area,MuR:Double):Double;
function HallVoltage(Current,B,Thickness,CarrierDensity,Charge:Double):Double;
function MutualInductance(L1,L2,K:Double):Double;
function TransformerInducedVoltage(M,DeltaCurrent,Dt:Double):Double;
procedure CoilStep(var C:TCoilModel;Voltage,Dt:Double);
implementation
function SolenoidField(const C:TCoilModel):Double;begin if C.Length<=0 then Exit(0);Result:=MU0*Max(1e-9,C.RelativePermeability)*C.Turns*C.Current/C.Length;end;
function MagneticFlux(B,Area:Double):Double;begin Result:=B*Area;end;
function CoilInductance(const C:TCoilModel):Double;begin if C.Length<=0 then Exit(0);Result:=MU0*Max(1e-9,C.RelativePermeability)*Sqr(C.Turns)*C.Area/C.Length;end;
function FaradayEMF(Turns:Integer;FluxNow,FluxPrevious,Dt:Double):Double;begin if Dt<=0 then Exit(0);Result:=-Turns*(FluxNow-FluxPrevious)/Dt;end;
function MagneticForce(B,Area,MuR:Double):Double;begin if MuR<=0 then MuR:=1;Result:=Sqr(B)*Area/(2*MU0*MuR);end;
function HallVoltage(Current,B,Thickness,CarrierDensity,Charge:Double):Double;begin if(Thickness<=0)or(CarrierDensity<=0)or(Charge=0)then Exit(0);Result:=Current*B/(CarrierDensity*Charge*Thickness);end;
function MutualInductance(L1,L2,K:Double):Double;begin Result:=Max(0,Min(1,K))*Sqrt(Max(0,L1)*Max(0,L2));end;
function TransformerInducedVoltage(M,DeltaCurrent,Dt:Double):Double;begin if Dt<=0 then Exit(0);Result:=-M*DeltaCurrent/Dt;end;
procedure CoilStep(var C:TCoilModel;Voltage,Dt:Double);var OldFlux,DI,B:Double;begin if(Dt<=0)or(C.Resistance<=0)then Exit;if C.Inductance<=0 then C.Inductance:=CoilInductance(C);if C.Inductance>0 then DI:=(Voltage-C.Resistance*C.Current)/C.Inductance*Dt else DI:=0;OldFlux:=C.Flux;C.Current:=C.Current+DI;B:=SolenoidField(C);C.Flux:=MagneticFlux(B,C.Area);C.FluxLinkage:=C.Turns*C.Flux;end;
end.
