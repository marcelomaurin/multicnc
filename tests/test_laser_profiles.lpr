program test_laser_profiles;
{$mode objfpc}{$H+}
uses Classes, SysUtils, multicnc_laser_profiles, multicnc_laser_config;
procedure Check(OK: Boolean; const Msg: string);
begin if not OK then raise Exception.Create(Msg); end;
var Brands,Models,Seen:TStringList; P,Ten:TLaserProfile; S:TLaserSettings;
    I,J,Total:Integer; Key:string;
begin
 try
  Brands:=TStringList.Create; Models:=TStringList.Create; Seen:=TStringList.Create;
  try
   GetLaserBrands(Brands); Total:=0;
   Check(Brands.Count=10,'manufacturers including CUSTOM');
   for I:=0 to Brands.Count-1 do begin
    GetLaserModels(Brands[I],Models);
    Check(Models.Count>0,'models for '+Brands[I]);
    for J:=0 to Models.Count-1 do begin
     Inc(Total); Key:=LowerCase(Brands[I]+'|'+Models[J]);
     Check(Seen.IndexOf(Key)<0,'unique profile '+Key); Seen.Add(Key);
     Check(FindLaserProfile(Brands[I],Models[J],P),'lookup '+Key);
     Check((P.WorkX>0) and (P.WorkY>0) and (P.OpticalPowerW>=0),'dimensions/power '+Key);
     if not SameText(P.Brand,'Generic') and not SameText(P.Brand,'GLYPHO') and not SameText(P.Brand,'CUSTOM') then
       Check((P.WorkX>0) and (P.WorkY>0) and (P.OpticalPowerW>0) and
         (Pos('https://',P.SourceURL)=1),'published commercial specifications '+Key);
     S:=LaserSettingsForProfile(P);
     Check((S.LaserPower>0) and (S.LaserPower<=100),'suggested percentage '+Key);
     Check((S.EngraveFeed>0) and (S.RapidFeed>=S.EngraveFeed),'suggested speeds '+Key);
     Check(not S.AirAssist and not S.FramingLaser and (S.PassZStep=0),'manual focus defaults '+Key);
     Check(S.WorkMode=lwmEngrave,'starts in engraving '+Key);
     Check(Pos('$30',LaserProfileSummary(P))>0,'S range explained '+Key);
    end;
   end;
   Check(Total=LASER_PROFILE_COUNT,'complete catalogue');
   Check(FindLaserProfile('CUSTOM','CUSTOM Laser',P) and
     (P.OpticalPowerW=0) and (P.SourceURL=''),'CUSTOM template requires operator specifications');
   Check(FindLaserProfile('glypho','s1 5w',P),'case insensitive GLYPHO');
   Check((P.WorkX=130) and (P.WorkY=130) and (P.OpticalPowerW=5),'5000mW interpreted as 5W');
   Check(FindLaserProfile('GLYPHO','S1 10W modificado',Ten),'modified GLYPHO');
   Check((Ten.WorkX=130) and (Ten.WorkY=130) and (Ten.OpticalPowerW=10),'modified geometry/power');
   Check(Ten.SuggestedPower<P.SuggestedPower,'lower percentage for stronger module');
   Check(FindLaserProfile('Ortur','Laser Master 3 20W',P) and
     (P.WorkX=400) and (P.WorkY=380) and (P.OpticalPowerW=20),'LM3 20W reduced area');
   Check(FindLaserProfile('LONGER','RAY5 20W',P) and
     (P.WorkX=400) and (P.WorkY=365) and (P.OpticalPowerW=20),'RAY5 20W reduced area');
   Check(FindLaserProfile('SCULPFUN','S30 Ultra 33W',P) and
     (P.WorkX=590) and (P.WorkY=595) and (P.OpticalPowerW=33),'Ultra actual working area');
   Check(FindLaserProfile('Creality','Falcon2 40W',P) and
     (P.WorkX=400) and (P.WorkY=415) and (P.OpticalPowerW=40),'Falcon2 specifications');
   Check(not FindLaserProfile('GLYPHO','missing',P) and (P.WorkX=0),'missing profile cleared');
   Writeln('PASS: laser profiles (',Total,' models)');
  finally Brands.Free; Models.Free; Seen.Free; end;
 except on E:Exception do begin Writeln('FAIL: ',E.Message); Halt(1); end; end;
end.
