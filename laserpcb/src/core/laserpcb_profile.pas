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
  Result.LaserSource := 0; Result.CopperUM := 35; Result.BoardMM := 1.6; Result.MaxFeed := 6000;
  Result.CopperEv := 0; Result.CutEv := 0;
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
    O.Add('laser_source', P.LaserSource); O.Add('copper_um', P.CopperUM);
    O.Add('board_mm', P.BoardMM); O.Add('max_feed', P.MaxFeed);
    O.Add('copper_ev', P.CopperEv); O.Add('cut_ev', P.CutEv);
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
      Result.LaserSource := EnsureRange(O.Get('laser_source', 0), 0, 2);
      Result.CopperUM := O.Get('copper_um', 35.0);
      Result.BoardMM := O.Get('board_mm', 1.6);
      Result.MaxFeed := O.Get('max_feed', 6000.0);
      if not (Result.CopperUM > 0) or not (Result.CopperUM < 1000) then Result.CopperUM := 35;
      if not (Result.BoardMM > 0) or not (Result.BoardMM < 20) then Result.BoardMM := 1.6;
      if not (Result.MaxFeed >= 60) or IsInfinite(Result.MaxFeed) then Result.MaxFeed := 6000;
      Result.CopperEv := O.Get('copper_ev', 0.0); Result.CutEv := O.Get('cut_ev', 0.0);
      if not (Result.CopperEv >= 0) or IsInfinite(Result.CopperEv) then Result.CopperEv := 0;
      if not (Result.CutEv >= 0) or IsInfinite(Result.CutEv) then Result.CutEv := 0;
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
