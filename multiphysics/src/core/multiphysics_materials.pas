unit multiphysics_materials;
{$mode objfpc}{$H+}
interface
uses multiphysics_types;
function Steel:TMaterial;function Aluminum:TMaterial;function ABSPlastic:TMaterial;
implementation
function Steel:TMaterial;begin Result.Name:='Aco carbono';Result.Density:=7850;Result.YoungModulus:=200e9;Result.Poisson:=0.30;Result.ThermalConductivity:=50;Result.SpecificHeat:=470;Result.ThermalExpansion:=12e-6;Result.YieldStrength:=250e6;end;
function Aluminum:TMaterial;begin Result.Name:='Aluminio';Result.Density:=2700;Result.YoungModulus:=69e9;Result.Poisson:=0.33;Result.ThermalConductivity:=205;Result.SpecificHeat:=900;Result.ThermalExpansion:=23e-6;Result.YieldStrength:=150e6;end;
function ABSPlastic:TMaterial;begin Result.Name:='ABS';Result.Density:=1040;Result.YoungModulus:=2.1e9;Result.Poisson:=0.35;Result.ThermalConductivity:=0.18;Result.SpecificHeat:=1300;Result.ThermalExpansion:=90e-6;Result.YieldStrength:=40e6;end;
end.
