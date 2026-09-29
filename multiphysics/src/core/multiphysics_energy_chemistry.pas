unit multiphysics_energy_chemistry;
{$mode objfpc}{$H+}
interface
uses Math,multiphysics_types;
type
 TFuel=record Name:string;Density,LowerHeatingValue,SpecificHeat:Double;Hazard:TChemicalHazard;end;
 TBatteryChemistry=(bcLeadAcid,bcNiMH,bcLiIon,bcLiFePO4);
 TBatteryModel=record Name:string;Chemistry:TBatteryChemistry;NominalVoltage,CapacityAh,SOC,InternalResistance,MaxChargeCurrent,MaxDischargeCurrent,Temperature:Double;end;
 TSolarPanel=record Name:string;RatedPower,Vmp,Imp,Voc,Isc,TemperatureCoefficient,Area:Double;end;
 TChemical=record Name:string;Formula:string;Density,SpecificHeat,BoilingPoint,FreezingPoint:Double;Hazard:TChemicalHazard;end;
function Gasoline:TFuel;function Diesel:TFuel;function EthanolFuel:TFuel;function LPG:TFuel;function HydrogenFuel:TFuel;
function LeadAcid12V(Ah:Double):TBatteryModel;function LiIonCell(Ah:Double):TBatteryModel;function LiFePO4Cell(Ah:Double):TBatteryModel;function NiMHCell(Ah:Double):TBatteryModel;
function BatteryTerminalVoltage(const B:TBatteryModel;Current:Double):Double;procedure BatteryStep(var B:TBatteryModel;Current,Dt:Double);
function SolarPower(const P:TSolarPanel;Irradiance,TemperatureC:Double):Double;
function Water:TChemical;function Ethanol:TChemical;function IsopropylAlcohol:TChemical;function Acetone:TChemical;function SodiumChloride:TChemical;function HydrochloricAcid:TChemical;
implementation
function Gasoline:TFuel;begin Result.Name:='Gasolina';Result.Density:=740;Result.LowerHeatingValue:=44e6;Result.SpecificHeat:=2200;Result.Hazard:=chFlammable;end;
function Diesel:TFuel;begin Result.Name:='Diesel';Result.Density:=840;Result.LowerHeatingValue:=43e6;Result.SpecificHeat:=2000;Result.Hazard:=chFlammable;end;
function EthanolFuel:TFuel;begin Result.Name:='Etanol combustivel';Result.Density:=789;Result.LowerHeatingValue:=26.8e6;Result.SpecificHeat:=2440;Result.Hazard:=chFlammable;end;
function LPG:TFuel;begin Result.Name:='GLP';Result.Density:=550;Result.LowerHeatingValue:=46e6;Result.SpecificHeat:=2400;Result.Hazard:=chFlammable;end;
function HydrogenFuel:TFuel;begin Result.Name:='Hidrogenio';Result.Density:=0.084;Result.LowerHeatingValue:=120e6;Result.SpecificHeat:=14300;Result.Hazard:=chFlammable;end;
function MakeBattery(const N:string;C:TBatteryChemistry;V,Ah,R,Chg,Dis:Double):TBatteryModel;begin Result.Name:=N;Result.Chemistry:=C;Result.NominalVoltage:=V;Result.CapacityAh:=Ah;Result.SOC:=1;Result.InternalResistance:=R;Result.MaxChargeCurrent:=Chg;Result.MaxDischargeCurrent:=Dis;Result.Temperature:=25;end;
function LeadAcid12V(Ah:Double):TBatteryModel;begin Result:=MakeBattery('Chumbo-acido 12 V',bcLeadAcid,12,Ah,0.02,0.3*Ah,5*Ah);end;
function LiIonCell(Ah:Double):TBatteryModel;begin Result:=MakeBattery('Li-ion 3.7 V',bcLiIon,3.7,Ah,0.05,Ah,3*Ah);end;
function LiFePO4Cell(Ah:Double):TBatteryModel;begin Result:=MakeBattery('LiFePO4 3.2 V',bcLiFePO4,3.2,Ah,0.03,Ah,3*Ah);end;
function NiMHCell(Ah:Double):TBatteryModel;begin Result:=MakeBattery('NiMH 1.2 V',bcNiMH,1.2,Ah,0.04,0.5*Ah,2*Ah);end;
function BatteryTerminalVoltage(const B:TBatteryModel;Current:Double):Double;begin Result:=Max(0,B.NominalVoltage*(0.9+0.1*B.SOC)-Current*B.InternalResistance);end;
procedure BatteryStep(var B:TBatteryModel;Current,Dt:Double);var D:Double;begin if(B.CapacityAh<=0)or(Dt<=0)then Exit;Current:=Max(-B.MaxChargeCurrent,Min(B.MaxDischargeCurrent,Current));D:=Current*Dt/3600/B.CapacityAh;B.SOC:=Max(0,Min(1,B.SOC-D));end;
function SolarPower(const P:TSolarPanel;Irradiance,TemperatureC:Double):Double;var F:Double;begin F:=1+P.TemperatureCoefficient*(TemperatureC-25);Result:=Max(0,P.RatedPower*(Irradiance/1000)*F);end;
function Chem(const N,F:string;D,C,BP,FP:Double;H:TChemicalHazard):TChemical;begin Result.Name:=N;Result.Formula:=F;Result.Density:=D;Result.SpecificHeat:=C;Result.BoilingPoint:=BP;Result.FreezingPoint:=FP;Result.Hazard:=H;end;
function Water:TChemical;begin Result:=Chem('Agua','H2O',998,4182,100,0,chNone);end;
function Ethanol:TChemical;begin Result:=Chem('Etanol','C2H6O',789,2440,78.4,-114,chFlammable);end;
function IsopropylAlcohol:TChemical;begin Result:=Chem('Alcool isopropilico','C3H8O',786,2600,82.6,-89,chFlammable);end;
function Acetone:TChemical;begin Result:=Chem('Acetona','C3H6O',784,2160,56,-95,chFlammable);end;
function SodiumChloride:TChemical;begin Result:=Chem('Cloreto de sodio','NaCl',2160,864,1465,801,chNone);end;
function HydrochloricAcid:TChemical;begin Result:=Chem('Acido cloridrico','HCl(aq)',1190,2500,110,-27,chCorrosive);end;
end.
