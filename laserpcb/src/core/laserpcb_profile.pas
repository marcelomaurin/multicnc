unit laserpcb_profile;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Math, fpjson, jsonparser, laserpcb_types;
type TLaserProfileIO = class
  public
    class procedure Save(const P: TLaserProfile; const FN: string);
    class function Load(const FN: string): TLaserProfile;
end;
function DefaultLaserProfile: TLaserProfile;
implementation
function DefaultLaserProfile: TLaserProfile;
begin
  Result.Name := ''; Result.OpticalPowerW := 0;
  Result.SpotMM := 0.1; Result.Power := 0; Result.Feed := 0;
  Result.SMax := 1000; Result.Passes := 1; Result.Process := lpMaskResist;
end;

class procedure TLaserProfileIO.Save(const P: TLaserProfile; const FN: string);
var O: TJSONObject; S: TStringList;
begin
  O := TJSONObject.Create; S := TStringList.Create;
  try
    O.Add('name', P.Name); O.Add('spot_mm', P.SpotMM);
    O.Add('power', P.Power); O.Add('feed', P.Feed);
    O.Add('s_max', P.SMax); O.Add('passes', P.Passes);
    O.Add('process', Ord(P.Process)); O.Add('optical_power_w',P.OpticalPowerW);
    S.Text := O.FormatJSON; S.SaveToFile(FN);
  finally S.Free; O.Free; end;
end;

class function TLaserProfileIO.Load(const FN: string): TLaserProfile;
var D: TJSONData; S: TStringList; O: TJSONObject; Mode: Integer;
begin
  Result := DefaultLaserProfile;
  if not FileExists(FN) then Exit;
  S := TStringList.Create;
  try
    S.LoadFromFile(FN); D := GetJSON(S.Text);
    try
      if not (D is TJSONObject) then raise Exception.Create('Perfil deve ser um objeto JSON');
      O := TJSONObject(D);
      Result.Name := O.Get('name', '');
      Result.OpticalPowerW := O.Get('optical_power_w',0.0);
      Result.SpotMM := O.Get('spot_mm', 0.1);
      Result.Power := O.Get('power', 0.0);
      Result.Feed := O.Get('feed', 0.0);
      Result.SMax := O.Get('s_max', 1000.0);
      Result.Passes := O.Get('passes', 1);
      Mode := O.Get('process', 0);
      if (Mode < Ord(Low(TLaserProcess))) or (Mode > Ord(High(TLaserProcess))) then
        raise Exception.Create('Processo do perfil invalido');
      Result.Process := TLaserProcess(Mode);
      if IsNan(Result.OpticalPowerW) or IsInfinite(Result.OpticalPowerW) or (Result.OpticalPowerW<0) or
        IsNan(Result.SpotMM) or IsInfinite(Result.SpotMM) or (Result.SpotMM <= 0) or
        IsNan(Result.SMax) or IsInfinite(Result.SMax) or (Result.SMax < 1) or
        IsNan(Result.Power) or IsInfinite(Result.Power) or (Result.Power < 0) or
        IsNan(Result.Feed) or IsInfinite(Result.Feed) or (Result.Feed < 0) or
        (Result.Power > Result.SMax) or (Result.Passes < 1) or (Result.Passes > 1000) then
        raise Exception.Create('Parametros invalidos no perfil laser');
    finally D.Free; end;
  finally S.Free; end;
end;
end.
