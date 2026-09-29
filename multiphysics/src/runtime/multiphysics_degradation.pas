unit multiphysics_degradation;
{$mode objfpc}{$H+}
interface
uses Math,multiphysics_types;
type
 TDegradationState=record InitialThickness,Thickness,OxideThickness,MassLoss,Integrity,ResistanceMultiplier:Double;end;
 TCorrosionEnvironment=record TemperatureC,RelativeHumidity,ChlorideFactor,AcidityFactor,OxygenFactor:Double;end;
 TCorrosionModel=record BaseRateMMPerYear,ActivationPer10C,HumidityThreshold:Double;end;
procedure InitDegradation(var S:TDegradationState;ThicknessMM:Double);
procedure CorrosionStep(var S:TDegradationState;const M:TMaterial;const E:TCorrosionEnvironment;const C:TCorrosionModel;DtSeconds:Double);
procedure OxidationStep(var S:TDegradationState;TemperatureC,OxygenFactor,BaseRateUMPerHour,DtSeconds:Double);
function EffectiveResistivity(const M:TMaterial;const S:TDegradationState):Double;
implementation
procedure InitDegradation(var S:TDegradationState;ThicknessMM:Double);begin FillChar(S,SizeOf(S),0);S.InitialThickness:=Max(1e-9,ThicknessMM);S.Thickness:=S.InitialThickness;S.Integrity:=1;S.ResistanceMultiplier:=1;end;
procedure CorrosionStep(var S:TDegradationState;const M:TMaterial;const E:TCorrosionEnvironment;const C:TCorrosionModel;DtSeconds:Double);var H,T,F,Loss:Double;begin if(DtSeconds<=0)or(S.Thickness<=0)then Exit;H:=Max(0,Min(1,(E.RelativeHumidity-C.HumidityThreshold)/Max(0.01,1-C.HumidityThreshold)));T:=Power(Max(0.1,C.ActivationPer10C),(E.TemperatureC-20)/10);F:=H*T*Max(0,E.OxygenFactor)*(1+Max(0,E.ChlorideFactor)+Max(0,E.AcidityFactor));Loss:=C.BaseRateMMPerYear*F*DtSeconds/(365.25*24*3600);S.Thickness:=Max(0,S.Thickness-Loss);S.MassLoss:=S.MassLoss+Loss*Max(0,M.Density);S.Integrity:=Max(0,Min(1,S.Thickness/S.InitialThickness));if S.Integrity>1e-6 then S.ResistanceMultiplier:=1/S.Integrity else S.ResistanceMultiplier:=1e9;end;
procedure OxidationStep(var S:TDegradationState;TemperatureC,OxygenFactor,BaseRateUMPerHour,DtSeconds:Double);var R:Double;begin if(DtSeconds<=0)then Exit;R:=Max(0,BaseRateUMPerHour)*Max(0,OxygenFactor)*Power(2,(TemperatureC-20)/50);S.OxideThickness:=S.OxideThickness+R*DtSeconds/3600;S.ResistanceMultiplier:=S.ResistanceMultiplier*(1+Min(0.01,R*DtSeconds/3600*1e-3));end;
function EffectiveResistivity(const M:TMaterial;const S:TDegradationState):Double;begin Result:=M.ElectricalResistivity*Max(1,S.ResistanceMultiplier);end;
end.
