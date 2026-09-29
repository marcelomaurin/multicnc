unit multicnc_profile;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpjson, jsonparser, multicnc_types;
type
 TMachineProfile=class
 public
  Name,Protocol,Transport,Device:string; MachineType:TMachineType;
  BaudRate:Integer; SizeX,SizeY,SizeZ:Double;
  constructor Create; function ToJSON:TJSONObject; procedure FromJSON(O:TJSONObject);
 end;
implementation
constructor TMachineProfile.Create; begin Name:='Nova maquina'; Protocol:='GRBL'; Transport:='Serial'; BaudRate:=115200; SizeX:=300;SizeY:=300;SizeZ:=100; end;
function TMachineProfile.ToJSON:TJSONObject;
begin Result:=TJSONObject.Create; Result.Add('name',Name); Result.Add('type',Ord(MachineType)); Result.Add('protocol',Protocol); Result.Add('transport',Transport); Result.Add('device',Device); Result.Add('baud',BaudRate); Result.Add('x',SizeX);Result.Add('y',SizeY);Result.Add('z',SizeZ); end;
procedure TMachineProfile.FromJSON(O:TJSONObject);
begin Name:=O.Get('name',''); MachineType:=TMachineType(O.Get('type',0)); Protocol:=O.Get('protocol','GRBL');Transport:=O.Get('transport','Serial');Device:=O.Get('device','');BaudRate:=O.Get('baud',115200);SizeX:=O.Get('x',0.0);SizeY:=O.Get('y',0.0);SizeZ:=O.Get('z',0.0); end;
end.
