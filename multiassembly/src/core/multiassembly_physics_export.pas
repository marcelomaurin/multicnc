unit multiassembly_physics_export;
{$mode objfpc}{$H+}
interface
uses SysUtils,multiassembly_types,multiassembly_project,multisuite_component_contract;
procedure ExportAssemblyToUnified(P:TAssemblyProject;U:TUnifiedMachine);
implementation
function DomainOf(K:TAssemblyComponentKind):set of TUnifiedDomain;begin case K of ackMotor:Result:=[udElectrical,udMechanical,udThermal];ackPowerSupply:Result:=[udElectrical];ackDriver,ackRelay,ackVFD,ackController,ackPCB:Result:=[udElectrical,udElectronic];ackSensor,ackEndStop:Result:=[udSensor,udElectrical];else Result:=[udMechanical];end;end;
procedure ExportAssemblyToUnified(P:TAssemblyProject;U:TUnifiedMachine);var I:Integer;A:TAssemblyComponent;C:TUnifiedComponent;W:TElectricalConnection;R:TMechanicalRelation;L:TUnifiedLink;begin U.Clear;for I:=0 to P.ComponentCount-1 do begin A:=P.Component(I);C:=TUnifiedComponent.Create(A.ID,A.Name);C.Model:=A.Model;C.Domains:=DomainOf(A.Kind);C.Parameters.Values['assembly_kind']:=IntToStr(Ord(A.Kind));C.Parameters.Values['x']:=FloatToStr(A.Position.X);C.Parameters.Values['y']:=FloatToStr(A.Position.Y);C.Parameters.Values['z']:=FloatToStr(A.Position.Z);U.Add(C);end;for I:=0 to P.WireCount-1 do begin W:=P.Wire(I);L.FromID:=W.FromComponent;L.FromPort:=W.FromPort;L.ToID:=W.ToComponent;L.ToPort:=W.ToPort;L.Kind:=upElectrical;U.Link(L);end;for I:=0 to P.RelationCount-1 do begin R:=P.Relation(I);L.FromID:=R.A;L.FromPort:='MECH';L.ToID:=R.B;L.ToPort:='MECH';if R.Kind=mrLeadScrew then L.Kind:=upLinear else L.Kind:=upRotary;U.Link(L);end;end;
end.
