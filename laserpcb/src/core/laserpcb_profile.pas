unit laserpcb_profile;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,fpjson,jsonparser,laserpcb_types;
type TLaserProfileIO=class public class procedure Save(const P:TLaserProfile;const FN:string);class function Load(const FN:string):TLaserProfile;end;
implementation
class procedure TLaserProfileIO.Save(const P:TLaserProfile;const FN:string);var O:TJSONObject;S:TStringList;begin O:=TJSONObject.Create;S:=TStringList.Create;try O.Add('name',P.Name);O.Add('spot_mm',P.SpotMM);O.Add('power',P.Power);O.Add('feed',P.Feed);O.Add('passes',P.Passes);O.Add('process',Ord(P.Process));S.Text:=O.FormatJSON;S.SaveToFile(FN);finally S.Free;O.Free;end;end;
class function TLaserProfileIO.Load(const FN:string):TLaserProfile;var D:TJSONData;S:TStringList;begin FillChar(Result,SizeOf(Result),0);Result.Passes:=1;if not FileExists(FN)then Exit;S:=TStringList.Create;try S.LoadFromFile(FN);D:=GetJSON(S.Text);try Result.Name:=TJSONObject(D).Get('name','');Result.SpotMM:=TJSONObject(D).Get('spot_mm',0.1);Result.Power:=TJSONObject(D).Get('power',0.0);Result.Feed:=TJSONObject(D).Get('feed',0.0);Result.Passes:=TJSONObject(D).Get('passes',1);Result.Process:=TLaserProcess(TJSONObject(D).Get('process',0));finally D.Free;end;finally S.Free;end;end;
end.
