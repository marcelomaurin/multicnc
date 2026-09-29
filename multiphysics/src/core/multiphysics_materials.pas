unit multiphysics_materials;
{$mode objfpc}{$H+}
interface
uses multiphysics_types;
function Steel:TMaterial;function Aluminum:TMaterial;function ABSPlastic:TMaterial;
function Iron:TMaterial;function PLAPlastic:TMaterial;function Acrylic:TMaterial;function Glass:TMaterial;
function Gold:TMaterial;function Silver:TMaterial;function Copper:TMaterial;function Lead:TMaterial;
implementation
function Steel:TMaterial;begin Result.Name:='Aco carbono';Result.Density:=7850;Result.YoungModulus:=200e9;Result.Poisson:=0.30;Result.ThermalConductivity:=50;Result.SpecificHeat:=470;Result.ThermalExpansion:=12e-6;Result.YieldStrength:=250e6;Result.ElectricalResistivity:=1.43e-7;end;
function Aluminum:TMaterial;begin Result.Name:='Aluminio';Result.Density:=2700;Result.YoungModulus:=69e9;Result.Poisson:=0.33;Result.ThermalConductivity:=205;Result.SpecificHeat:=900;Result.ThermalExpansion:=23e-6;Result.YieldStrength:=150e6;Result.ElectricalResistivity:=2.82e-8;end;
function ABSPlastic:TMaterial;begin Result.Name:='ABS';Result.Density:=1040;Result.YoungModulus:=2.1e9;Result.Poisson:=0.35;Result.ThermalConductivity:=0.18;Result.SpecificHeat:=1300;Result.ThermalExpansion:=90e-6;Result.YieldStrength:=40e6;Result.ElectricalResistivity:=1e14;end;
function Iron:TMaterial;begin Result.Name:='Ferro puro';Result.Density:=7874;Result.YoungModulus:=211e9;Result.Poisson:=0.29;Result.ThermalConductivity:=80.4;Result.SpecificHeat:=449;Result.ThermalExpansion:=11.8e-6;Result.YieldStrength:=50e6;Result.ElectricalResistivity:=9.71e-8;end;
function PLAPlastic:TMaterial;begin Result.Name:='PLA';Result.Density:=1240;Result.YoungModulus:=3.5e9;Result.Poisson:=0.36;Result.ThermalConductivity:=0.13;Result.SpecificHeat:=1800;Result.ThermalExpansion:=68e-6;Result.YieldStrength:=60e6;Result.ElectricalResistivity:=1e14;end;
function Acrylic:TMaterial;begin Result.Name:='Acrilico PMMA';Result.Density:=1180;Result.YoungModulus:=3.2e9;Result.Poisson:=0.35;Result.ThermalConductivity:=0.19;Result.SpecificHeat:=1470;Result.ThermalExpansion:=70e-6;Result.YieldStrength:=65e6;Result.ElectricalResistivity:=1e13;end;
function Glass:TMaterial;begin Result.Name:='Vidro soda-cal generico';Result.Density:=2500;Result.YoungModulus:=70e9;Result.Poisson:=0.22;Result.ThermalConductivity:=1.0;Result.SpecificHeat:=840;Result.ThermalExpansion:=9e-6;Result.YieldStrength:=33e6;Result.ElectricalResistivity:=1e10;end;
function Gold:TMaterial;begin Result.Name:='Ouro';Result.Density:=19320;Result.YoungModulus:=79e9;Result.Poisson:=0.44;Result.ThermalConductivity:=318;Result.SpecificHeat:=129;Result.ThermalExpansion:=14.2e-6;Result.YieldStrength:=100e6;Result.ElectricalResistivity:=2.44e-8;end;
function Silver:TMaterial;begin Result.Name:='Prata';Result.Density:=10490;Result.YoungModulus:=83e9;Result.Poisson:=0.37;Result.ThermalConductivity:=429;Result.SpecificHeat:=235;Result.ThermalExpansion:=18.9e-6;Result.YieldStrength:=55e6;Result.ElectricalResistivity:=1.59e-8;end;
function Copper:TMaterial;begin Result.Name:='Cobre';Result.Density:=8960;Result.YoungModulus:=110e9;Result.Poisson:=0.34;Result.ThermalConductivity:=401;Result.SpecificHeat:=385;Result.ThermalExpansion:=16.5e-6;Result.YieldStrength:=70e6;Result.ElectricalResistivity:=1.68e-8;end;
function Lead:TMaterial;begin Result.Name:='Chumbo';Result.Density:=11340;Result.YoungModulus:=16e9;Result.Poisson:=0.44;Result.ThermalConductivity:=35.3;Result.SpecificHeat:=128;Result.ThermalExpansion:=28.9e-6;Result.YieldStrength:=12e6;Result.ElectricalResistivity:=2.2e-7;end;
end.
