unit multisuite_component_contract;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils;
type
 TUnifiedDomain=(udElectrical,udElectronic,udMechanical,udThermal,udSensor,udControl);
 TUnifiedPortKind=(upElectrical,upRotary,upLinear,upThermal,upSignal);
 TUnifiedComponent=class
 public ID,Name,Model:string;Domains:set of TUnifiedDomain;Parameters:TStringList;
  constructor Create(const AID,AName:string);destructor Destroy;override;
 end;
 TUnifiedLink=record FromID,FromPort,ToID,ToPort:string;Kind:TUnifiedPortKind;end;
 TUnifiedMachine=class
 private FComponents:TList;FLinks:array of TUnifiedLink;
 public constructor Create;destructor Destroy;override;procedure Clear;function Add(C:TUnifiedComponent):Boolean;procedure Link(const L:TUnifiedLink);function Find(const ID:string):TUnifiedComponent;function Count:Integer;function Component(I:Integer):TUnifiedComponent;function LinkCount:Integer;function GetLink(I:Integer):TUnifiedLink;
 end;
implementation
constructor TUnifiedComponent.Create(const AID,AName:string);begin inherited Create;ID:=AID;Name:=AName;Parameters:=TStringList.Create;end;
destructor TUnifiedComponent.Destroy;begin Parameters.Free;inherited;end;
constructor TUnifiedMachine.Create;begin inherited;FComponents:=TList.Create;end;
destructor TUnifiedMachine.Destroy;begin Clear;FComponents.Free;inherited;end;
procedure TUnifiedMachine.Clear;var I:Integer;begin for I:=0 to FComponents.Count-1 do TObject(FComponents[I]).Free;FComponents.Clear;SetLength(FLinks,0);end;
function TUnifiedMachine.Find(const ID:string):TUnifiedComponent;var I:Integer;begin Result:=nil;for I:=0 to FComponents.Count-1 do if SameText(TUnifiedComponent(FComponents[I]).ID,ID)then Exit(TUnifiedComponent(FComponents[I]));end;
function TUnifiedMachine.Add(C:TUnifiedComponent):Boolean;begin Result:=(C<>nil)and(C.ID<>'')and(Find(C.ID)=nil);if Result then FComponents.Add(C);end;
procedure TUnifiedMachine.Link(const L:TUnifiedLink);var N:Integer;begin N:=Length(FLinks);SetLength(FLinks,N+1);FLinks[N]:=L;end;
function TUnifiedMachine.Count:Integer;begin Result:=FComponents.Count;end;function TUnifiedMachine.Component(I:Integer):TUnifiedComponent;begin Result:=TUnifiedComponent(FComponents[I]);end;function TUnifiedMachine.LinkCount:Integer;begin Result:=Length(FLinks);end;function TUnifiedMachine.GetLink(I:Integer):TUnifiedLink;begin Result:=FLinks[I];end;
end.
