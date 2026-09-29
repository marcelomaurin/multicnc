unit multipcb_model;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,multipcb_types;
type
 TPCBComponent=class
 public Ref,Value,LibraryID,FootprintID:string;X,Y,Rotation:Double;Pins:array of TPin;Pads:array of TPad;end;
 TNet=class
 public Name:string;Nodes:TStringList;constructor Create;destructor Destroy;override;end;
 TPCBProject=class
 public Name:string;Components, Nets:TList;BoardWidth,BoardHeight:Double;
  constructor Create;destructor Destroy;override;function AddComponent(const ARef,AValue,ALib,AFoot:string):TPCBComponent;function AddNet(const AName:string):TNet;
 end;
implementation
constructor TNet.Create;begin Nodes:=TStringList.Create;end;
destructor TNet.Destroy;begin Nodes.Free;inherited;end;
constructor TPCBProject.Create;begin Components:=TList.Create;Nets:=TList.Create;BoardWidth:=100;BoardHeight:=80;end;
destructor TPCBProject.Destroy;var I:Integer;begin for I:=0 to Components.Count-1 do TObject(Components[I]).Free;for I:=0 to Nets.Count-1 do TObject(Nets[I]).Free;Components.Free;Nets.Free;inherited;end;
function TPCBProject.AddComponent(const ARef,AValue,ALib,AFoot:string):TPCBComponent;begin Result:=TPCBComponent.Create;Result.Ref:=ARef;Result.Value:=AValue;Result.LibraryID:=ALib;Result.FootprintID:=AFoot;Components.Add(Result);end;
function TPCBProject.AddNet(const AName:string):TNet;begin Result:=TNet.Create;Result.Name:=AName;Nets.Add(Result);end;
end.
