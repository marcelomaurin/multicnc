unit multipcb_physics_export;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,multipcb_model,multisuite_component_contract;
procedure ExportPCBToUnified(P:TPCBProject;U:TUnifiedMachine;PreserveExisting:Boolean=True);
implementation
type TDomainSet=set of TUnifiedDomain;
function DomainsFor(const C:TPCBComponent):TDomainSet;var S:string;begin S:=LowerCase(C.Value+' '+C.LibraryID);Result:=[udElectrical,udElectronic];if(Pos('motor',S)>0)or(Pos('fan',S)>0)then Include(Result,udMechanical);if(Pos('sensor',S)>0)or(Pos('encoder',S)>0)then Include(Result,udSensor);if(Pos('mcu',S)>0)or(Pos('controller',S)>0)then Include(Result,udControl);end;
procedure ExportPCBToUnified(P:TPCBProject;U:TUnifiedMachine;PreserveExisting:Boolean);var I,J,K:Integer;C:TPCBComponent;UC:TUnifiedComponent;N:TNet;Node,Ref,Pin:string;Sep:SizeInt;L:TUnifiedLink;
begin if not PreserveExisting then U.Clear;for I:=0 to P.Components.Count-1 do begin C:=TPCBComponent(P.Components[I]);UC:=U.Find(C.Ref);if UC=nil then begin UC:=TUnifiedComponent.Create(C.Ref,C.Value);U.Add(UC);end;UC.Model:=C.LibraryID;UC.Domains:=UC.Domains+DomainsFor(C);UC.Parameters.Values['pcb_ref']:=C.Ref;UC.Parameters.Values['value']:=C.Value;UC.Parameters.Values['footprint']:=C.FootprintID;end;
for I:=0 to P.Nets.Count-1 do begin N:=TNet(P.Nets[I]);for J:=0 to N.Nodes.Count-1 do begin Node:=Trim(N.Nodes[J]);Sep:=Pos('.',Node);if Sep=0 then Sep:=Pos(':',Node);if Sep>0 then begin Ref:=Copy(Node,1,Sep-1);Pin:=Copy(Node,Sep+1,MaxInt);UC:=U.Find(Ref);if UC<>nil then UC.Parameters.Values['net.'+Pin]:=N.Name;end;end;for J:=0 to N.Nodes.Count-2 do for K:=J+1 to N.Nodes.Count-1 do begin Sep:=Pos('.',N.Nodes[J]);if Sep=0 then Sep:=Pos(':',N.Nodes[J]);if Sep=0 then Continue;L.FromID:=Copy(N.Nodes[J],1,Sep-1);L.FromPort:=Copy(N.Nodes[J],Sep+1,MaxInt);Sep:=Pos('.',N.Nodes[K]);if Sep=0 then Sep:=Pos(':',N.Nodes[K]);if Sep=0 then Continue;L.ToID:=Copy(N.Nodes[K],1,Sep-1);L.ToPort:=Copy(N.Nodes[K],Sep+1,MaxInt);L.Kind:=upElectrical;if(U.Find(L.FromID)<>nil)and(U.Find(L.ToID)<>nil)then U.Link(L);end;end;end;
end.
