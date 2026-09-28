unit uDomain;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, IniFiles, Math;
type
  TVector = record X,Y,Z: Double; end;
  TVectors = array of TVector;
  TDeviceConfig = record
    ID, Name, Kind, Brand, Model, Port, Protocol: string;
    Baud: Integer;
    DTR, RTS, StatusInches, RealtimeMarlin: Boolean;
  end;
  TDeviceConfigs = array of TDeviceConfig;
  TSnapshot = record
    State, MachineState, FrameName, Quality, LastError, LogText: string;
    Connected, Ready, Running, Paused: Boolean;
    Position: TVector;
    HasPosition: Boolean;
    LastPositionTick: QWord;
    Accepted, Total: Integer;
    Trail: TVectors;
  end;
  TModelProfile = record Brand, Model, Kind, Protocol: string; Baud: Integer; end;
const
  ModelCount = 11;
  ModelProfiles: array[0..ModelCount-1] of TModelProfile = (
    (Brand:'MultiCNC';Model:'Simulador vetorial';Kind:'laser';Protocol:'simulator';Baud:115200),
    (Brand:'SainSmart Genmitsu';Model:'3018-PRO';Kind:'router';Protocol:'grbl';Baud:115200),
    (Brand:'SainSmart Genmitsu';Model:'3018-PROVer';Kind:'router';Protocol:'grbl';Baud:115200),
    (Brand:'SainSmart Genmitsu';Model:'4040-PRO';Kind:'router';Protocol:'grbl';Baud:115200),
    (Brand:'SCULPFUN';Model:'S9';Kind:'laser';Protocol:'grbl';Baud:115200),
    (Brand:'SCULPFUN';Model:'S30';Kind:'laser';Protocol:'grbl';Baud:115200),
    (Brand:'ORTUR';Model:'Laser Master 2';Kind:'laser';Protocol:'grbl';Baud:115200),
    (Brand:'xTool';Model:'D1 Pro';Kind:'laser';Protocol:'grbl';Baud:115200),
    (Brand:'Creality';Model:'Ender-3 original';Kind:'printer';Protocol:'marlin';Baud:115200),
    (Brand:'Prusa';Model:'i3 MK3S / MK3S+';Kind:'printer';Protocol:'marlin';Baud:115200),
    (Brand:'Personalizado';Model:'Confirmar firmware';Kind:'router';Protocol:'grbl';Baud:115200));
function ConfigPath: string;
procedure ValidateConfig(const C:TDeviceConfig);
function LoadConfigs(const FileName:string):TDeviceConfigs;
procedure SaveConfigs(const FileName:string; const Items:TDeviceConfigs);
function DotFloat(const S:string; out V:Double):Boolean;
function Vector(X,Y,Z:Double):TVector;
implementation
function Vector(X,Y,Z:Double):TVector;
begin Result.X:=X;Result.Y:=Y;Result.Z:=Z;end;
function DotFloat(const S:string; out V:Double):Boolean;
var F:TFormatSettings;
begin F:=DefaultFormatSettings;F.DecimalSeparator:='.'; Result:=TryStrToFloat(S,V,F);if Result then Result:=not IsNan(V) and not IsInfinite(V);end;
function ConfigPath:string;
begin Result:=IncludeTrailingPathDelimiter(GetEnvironmentVariable('LOCALAPPDATA'))+'MultiCNC'+DirectorySeparator+'devices.ini';end;
procedure ValidateConfig(const C:TDeviceConfig);
var N:Integer;
begin
  if (Trim(C.Name)='') or (Trim(C.Brand)='') or (Trim(C.Model)='') then raise Exception.Create('Informe nome, marca e modelo.');
  if (C.Kind<>'laser') and (C.Kind<>'router') and (C.Kind<>'printer') then raise Exception.Create('Tipo inválido.');
  if (C.Protocol<>'grbl') and (C.Protocol<>'marlin') and (C.Protocol<>'simulator') then raise Exception.Create('Protocolo inválido.');
  if (C.Baud<1200) or (C.Baud>1000000) then raise Exception.Create('Baud rate fora do intervalo 1200..1000000.');
  if C.Protocol<>'simulator' then begin
    if (Copy(C.Port,1,3)<>'COM') or not TryStrToInt(Copy(C.Port,4,20),N) or (N<1) or (C.Port<>'COM'+IntToStr(N)) then raise Exception.Create('Informe uma porta no formato COM3.');
  end;
end;
function LoadConfigs(const FileName:string):TDeviceConfigs;
var I:TMemIniFile;Sections:TStringList;N:Integer;C:TDeviceConfig;S:string;
begin
  Result:=nil;if not FileExists(FileName) then Exit;
  I:=TMemIniFile.Create(FileName);Sections:=TStringList.Create;
  try
    I.ReadSections(Sections);
    for N:=0 to Sections.Count-1 do begin S:=Sections[N];if Copy(S,1,7)<>'device.' then Continue;
      C.ID:=Copy(S,8,100);C.Name:=I.ReadString(S,'name','');C.Kind:=I.ReadString(S,'kind','');C.Brand:=I.ReadString(S,'brand','');C.Model:=I.ReadString(S,'model','');
      C.Port:=I.ReadString(S,'port','');C.Protocol:=I.ReadString(S,'protocol','');C.Baud:=I.ReadInteger(S,'baud',115200);
      C.DTR:=I.ReadBool(S,'dtr',False);C.RTS:=I.ReadBool(S,'rts',False);C.StatusInches:=I.ReadBool(S,'status_inches',False);C.RealtimeMarlin:=I.ReadBool(S,'marlin_realtime',False);
      ValidateConfig(C);SetLength(Result,Length(Result)+1);Result[High(Result)]:=C;
    end;
  finally I.Free;Sections.Free;end;
end;
procedure SaveConfigs(const FileName:string; const Items:TDeviceConfigs);
var I:TMemIniFile;C:TDeviceConfig;S,Tmp:string;
begin
  ForceDirectories(ExtractFileDir(FileName));Tmp:=FileName+'.tmp';if FileExists(Tmp) then DeleteFile(Tmp);
  I:=TMemIniFile.Create(Tmp);
  try for C in Items do begin ValidateConfig(C);S:='device.'+C.ID;
    I.WriteString(S,'name',C.Name);I.WriteString(S,'kind',C.Kind);I.WriteString(S,'brand',C.Brand);I.WriteString(S,'model',C.Model);I.WriteString(S,'port',C.Port);I.WriteString(S,'protocol',C.Protocol);I.WriteInteger(S,'baud',C.Baud);
    I.WriteBool(S,'dtr',C.DTR);I.WriteBool(S,'rts',C.RTS);I.WriteBool(S,'status_inches',C.StatusInches);I.WriteBool(S,'marlin_realtime',C.RealtimeMarlin);
  end;I.UpdateFile;finally I.Free;end;
  if FileExists(FileName) then begin
    if FileExists(FileName+'.bak') then if not DeleteFile(FileName+'.bak') then raise Exception.Create('Não foi possível substituir backup.');
    if not RenameFile(FileName,FileName+'.bak') then raise Exception.Create('Não foi possível salvar backup.');
  end;
  if not RenameFile(Tmp,FileName) then begin RenameFile(FileName+'.bak',FileName);raise Exception.Create('Falha ao salvar cadastro.');end;
end;
end.
