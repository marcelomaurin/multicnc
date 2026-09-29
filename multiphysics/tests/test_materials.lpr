program test_materials;
{$mode objfpc}{$H+}
uses multiphysics_types,multiphysics_materials;
var M:TMaterial;
procedure Check(const X:TMaterial);begin if(X.Density<=0)or(X.YoungModulus<=0)or(X.ThermalConductivity<=0)or(X.SpecificHeat<=0)or(X.ElectricalResistivity<=0)then Halt(1);end;
begin Check(Steel);Check(Aluminum);Check(ABSPlastic);Check(Iron);Check(PLAPlastic);Check(Acrylic);Check(Glass);Check(Gold);Check(Silver);Check(Copper);Check(Lead);M:=Copper;if M.ElectricalResistivity>=Lead.ElectricalResistivity then Halt(2);Writeln('PASS materials library');end.
