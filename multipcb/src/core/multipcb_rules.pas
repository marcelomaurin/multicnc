unit multipcb_rules;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,multipcb_model,multipcb_types;
type TMultipcbRules=class
 public class procedure ERC(P:TPCBProject;Errors:TStrings);class procedure DRC(P:TPCBProject;Errors:TStrings);
 end;
implementation
class procedure TMultipcbRules.ERC(P:TPCBProject;Errors:TStrings);
var I,J:Integer;N:TNet;
begin Errors.Clear;for I:=0 to P.Nets.Count-1 do begin N:=TNet(P.Nets[I]);if N.Nodes.Count<2 then Errors.Add('ERC: net '+N.Name+' possui menos de 2 conexoes');for J:=0 to N.Nodes.Count-1 do if Trim(N.Nodes[J])='' then Errors.Add('ERC: conexao vazia em '+N.Name);end;end;
class procedure TMultipcbRules.DRC(P:TPCBProject;Errors:TStrings);
var I:Integer;C:TPCBComponent;
begin Errors.Clear;if(P.BoardWidth<=0)or(P.BoardHeight<=0)then Errors.Add('DRC: dimensoes da placa invalidas');for I:=0 to P.Components.Count-1 do begin C:=TPCBComponent(P.Components[I]);if(C.X<0)or(C.Y<0)or(C.X>P.BoardWidth)or(C.Y>P.BoardHeight)then Errors.Add('DRC: '+C.Ref+' fora da placa');end;end;
end.
