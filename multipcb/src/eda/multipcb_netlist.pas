unit multipcb_netlist;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,multipcb_model;
type
 TNetEndpoint=record ComponentRef,PinNumber,PadNumber:string;end;
 TNetConnection=class
 public Name:string;Endpoints:array of TNetEndpoint;procedure Add(const Ref,Pin,Pad:string);end;
 TNetlist=class
 private FItems:TList;
 public constructor Create;destructor Destroy;override;procedure Clear;function AddNet(const Name:string):TNetConnection;function Find(const Name:string):TNetConnection;function Count:Integer;function Net(I:Integer):TNetConnection;
 end;
implementation
procedure TNetConnection.Add(const Ref,Pin,Pad:string);var N:Integer;begin N:=Length(Endpoints);SetLength(Endpoints,N+1);Endpoints[N].ComponentRef:=Ref;Endpoints[N].PinNumber:=Pin;Endpoints[N].PadNumber:=Pad;end;
constructor TNetlist.Create;begin FItems:=TList.Create;end;destructor TNetlist.Destroy;begin Clear;FItems.Free;inherited;end;
procedure TNetlist.Clear;var I:Integer;begin for I:=FItems.Count-1 downto 0 do TObject(FItems[I]).Free;FItems.Clear;end;
function TNetlist.AddNet(const Name:string):TNetConnection;begin Result:=Find(Name);if Assigned(Result)then Exit;Result:=TNetConnection.Create;Result.Name:=Name;FItems.Add(Result);end;
function TNetlist.Find(const Name:string):TNetConnection;var I:Integer;begin Result:=nil;for I:=0 to FItems.Count-1 do if SameText(TNetConnection(FItems[I]).Name,Name)then Exit(TNetConnection(FItems[I]));end;
function TNetlist.Count:Integer;begin Result:=FItems.Count;end;function TNetlist.Net(I:Integer):TNetConnection;begin Result:=TNetConnection(FItems[I]);end;
end.
