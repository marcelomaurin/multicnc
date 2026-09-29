program test_materials;
{$mode objfpc}{$H+}
uses multiphysics_types,multiphysics_materials;
var M:TMaterial;
procedure Check(const X:TMaterial);begin if(X.Density<=0)or(X.YoungModulus<=0)or(X.ThermalConductivity<=0)or(X.SpecificHeat<=0)or(X.ElectricalResistivity<=0)then Halt(1);end;
begin Check(Steel);Check(Aluminum);Check(ABSPlastic);Check(Iron);Check(PLAPlastic);Check(Acrylic);Check(Glass);Check(Gold);Check(Silver);Check(Copper);Check(Lead);Check(StainlessSteel304);Check(Brass);Check(Bronze);Check(Titanium);Check(PETGPlastic);Check(Nylon);Check(PVC);Check(PTFE);Check(SiliconeRubber);Check(NaturalRubber);Check(FR4);Check(Silicon);Check(AluminaCeramic);Check(WoodGeneric);M:=Copper;if M.ElectricalResistivity>=Lead.ElectricalResistivity then Halt(2);M:=FR4;CompleteMaterial(M);if M.MaterialClass<>mcComposite then Halt(3);M:=PLAPlastic;CompleteMaterial(M);if M.MaxServiceTemperature<=0 then Halt(4);Writeln('PASS expanded materials library');end.
