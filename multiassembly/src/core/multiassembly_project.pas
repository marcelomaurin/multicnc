unit multiassembly_project;
{$mode objfpc}{$H+}
interface
uses SysUtils,multiassembly_types;
type TAssemblyProject=class
 private FComponents:array of TAssemblyComponent;FWires:array of TElectricalConnection;FRelations:array of TMechanicalRelation;
 public Name:string;procedure Clear;procedure AddComponent(const C:TAssemblyComponent);procedure Connect(const W:TElectricalConnection);procedure Relate(const R:TMechanicalRelation);function ComponentCount:Integer;function WireCount:Integer;function RelationCount:Integer;function Component(I:Integer):TAssemblyComponent;function Wire(I:Integer):TElectricalConnection;function Relation(I:Integer):TMechanicalRelation;function FindComponent(const ID:string):Integer;
 end;
implementation
procedure TAssemblyProject.Clear;begin SetLength(FComponents,0);SetLength(FWires,0);SetLength(FRelations,0);end;
procedure TAssemblyProject.AddComponent(const C:TAssemblyComponent);var N:Integer;begin if C.ID='' then raise Exception.Create('Componente sem ID');if FindComponent(C.ID)>=0 then raise Exception.Create('ID duplicado: '+C.ID);N:=Length(FComponents);SetLength(FComponents,N+1);FComponents[N]:=C;end;
procedure TAssemblyProject.Connect(const W:TElectricalConnection);var N:Integer;begin N:=Length(FWires);SetLength(FWires,N+1);FWires[N]:=W;end;
procedure TAssemblyProject.Relate(const R:TMechanicalRelation);var N:Integer;begin N:=Length(FRelations);SetLength(FRelations,N+1);FRelations[N]:=R;end;
function TAssemblyProject.ComponentCount:Integer;begin Result:=Length(FComponents);end;function TAssemblyProject.WireCount:Integer;begin Result:=Length(FWires);end;function TAssemblyProject.RelationCount:Integer;begin Result:=Length(FRelations);end;function TAssemblyProject.Component(I:Integer):TAssemblyComponent;begin Result:=FComponents[I];end;function TAssemblyProject.Wire(I:Integer):TElectricalConnection;begin Result:=FWires[I];end;function TAssemblyProject.Relation(I:Integer):TMechanicalRelation;begin Result:=FRelations[I];end;
function TAssemblyProject.FindComponent(const ID:string):Integer;var I:Integer;begin Result:=-1;for I:=0 to High(FComponents)do if SameText(FComponents[I].ID,ID)then Exit(I);end;
end.
