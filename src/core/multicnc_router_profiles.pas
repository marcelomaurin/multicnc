unit multicnc_router_profiles;

{ Perfis de marca/modelo de CNC Router (fresadora). Valores conferidos nas
  paginas dos fabricantes (out/2026). 0 em SpindlePowerW/SpindleMaxRPM = nao
  informado pelo fabricante. O curso X/Y/Z e editavel na tela, porque cada
  maquina montada pode diferir (mesa, fixacao, upgrades). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TRouterProfile = record
    Brand: string;
    Model: string;
    WorkX: Double;         { mm }
    WorkY: Double;         { mm }
    WorkZ: Double;         { mm }
    BaudRate: Integer;
    SpindlePowerW: Integer;
    SpindleMaxRPM: Integer;
    ColletType: string;
    Firmware: string;
    Notes: string;
  end;

const
  ROUTER_PROFILE_COUNT = 22;

procedure GetRouterBrands(AList: TStrings);
procedure GetRouterModels(const ABrand: string; AList: TStrings);
function FindRouterProfile(const ABrand, AModel: string; out AProfile: TRouterProfile): Boolean;
function RouterProfileSummary(const P: TRouterProfile): string;
{ Texto do spindle; trata valores nao informados (0). }
function SpindleText(const P: TRouterProfile): string;

implementation

const
  PROFILES: array[0..ROUTER_PROFILE_COUNT - 1] of TRouterProfile = (
    // Generic
    (
      Brand: 'Generic';
      Model: 'Generic GRBL Router';
      WorkX: 300.0; WorkY: 180.0; WorkZ: 45.0;
      BaudRate: 115200;
      SpindlePowerW: 0; SpindleMaxRPM: 0;
      ColletType: '';
      Firmware: 'GRBL 1.1';
      Notes: 'Generic machine: adjust the X/Y/Z travel fields to your machine before jogging'
    ),
    (
      Brand: 'Generic';
      Model: 'Mini Fresadora CNC 3018 Router 3 Eixos';
      WorkX: 300.0; WorkY: 180.0; WorkZ: 45.0;
      BaudRate: 115200;
      SpindlePowerW: 0; SpindleMaxRPM: 0;
      ColletType: '';
      Firmware: 'GRBL 1.1';
      Notes: 'Unbranded 3018 kit (typically 775 spindle); confirm travel and $30 on your board'
    ),
    // SainSmart / Genmitsu
    (
      Brand: 'SainSmart / Genmitsu';
      Model: '3018-PRO';
      WorkX: 300.0; WorkY: 180.0; WorkZ: 45.0;
      BaudRate: 115200;
      SpindlePowerW: 0; SpindleMaxRPM: 20000;
      ColletType: '';
      Firmware: 'GRBL 1.1f';
      Notes: 'V2 control board; early units shipped with a 775 spindle (about 9000-10000 RPM)'
    ),
    (
      Brand: 'SainSmart / Genmitsu';
      Model: '3018-PROVer';
      WorkX: 260.0; WorkY: 155.0; WorkZ: 35.0;
      BaudRate: 115200;
      SpindlePowerW: 120; SpindleMaxRPM: 10000;
      ColletType: '';
      Firmware: 'GRBL';
      Notes: '775 spindle, 60 W rated / 120 W max, 12-24 V; effective engraving area'
    ),
    (
      Brand: 'SainSmart / Genmitsu';
      Model: '3020-PRO MAX';
      WorkX: 300.0; WorkY: 200.0; WorkZ: 72.0;
      BaudRate: 115200;
      SpindlePowerW: 300; SpindleMaxRPM: 12000;
      ColletType: '';
      Firmware: 'GRBL';
      Notes: '300 W spindle'
    ),
    (
      Brand: 'SainSmart / Genmitsu';
      Model: 'PROVerXL 4030 V2';
      WorkX: 400.0; WorkY: 300.0; WorkZ: 110.0;
      BaudRate: 115200;
      SpindlePowerW: 400; SpindleMaxRPM: 10000;
      ColletType: '';
      Firmware: 'GRBL 1.1h';
      Notes: '400 W DC spindle (0-48 V); max feed 5000 mm/min'
    ),
    (
      Brand: 'SainSmart / Genmitsu';
      Model: '4040-PRO';
      WorkX: 400.0; WorkY: 400.0; WorkZ: 78.0;
      BaudRate: 115200;
      SpindlePowerW: 75; SpindleMaxRPM: 9000;
      ColletType: '';
      Firmware: 'GRBL (32-bit MCU)';
      Notes: '75 W spindle, 42/52 mm mounts; max feed 2000 mm/min'
    ),
    // Carbide 3D
    (
      Brand: 'Carbide 3D';
      Model: 'Shapeoko 4 Standard';
      WorkX: 444.5; WorkY: 444.5; WorkZ: 101.6;
      BaudRate: 115200;
      SpindlePowerW: 0; SpindleMaxRPM: 0;
      ColletType: '';
      Firmware: 'GRBL 1.1';
      Notes: 'Router not included: fit a 65 mm trim router or VFD spindle'
    ),
    (
      Brand: 'Carbide 3D';
      Model: 'Shapeoko 4 XL';
      WorkX: 838.2; WorkY: 444.5; WorkZ: 101.6;
      BaudRate: 115200;
      SpindlePowerW: 0; SpindleMaxRPM: 0;
      ColletType: '';
      Firmware: 'GRBL 1.1';
      Notes: 'Router not included: fit a 65 mm trim router or VFD spindle'
    ),
    (
      Brand: 'Carbide 3D';
      Model: 'Shapeoko 4 XXL';
      WorkX: 838.2; WorkY: 838.2; WorkZ: 101.6;
      BaudRate: 115200;
      SpindlePowerW: 0; SpindleMaxRPM: 0;
      ColletType: '';
      Firmware: 'GRBL 1.1';
      Notes: 'Router not included: fit a 65 mm trim router or VFD spindle'
    ),
    (
      Brand: 'Carbide 3D';
      Model: 'Shapeoko Pro Standard';
      WorkX: 444.5; WorkY: 444.5; WorkZ: 101.6;
      BaudRate: 115200;
      SpindlePowerW: 0; SpindleMaxRPM: 0;
      ColletType: '';
      Firmware: 'GRBL 1.1';
      Notes: 'Linear rails; router not included (65 mm trim router or VFD spindle)'
    ),
    (
      Brand: 'Carbide 3D';
      Model: 'Shapeoko Pro XL';
      WorkX: 838.2; WorkY: 444.5; WorkZ: 101.6;
      BaudRate: 115200;
      SpindlePowerW: 0; SpindleMaxRPM: 0;
      ColletType: '';
      Firmware: 'GRBL 1.1';
      Notes: 'Linear rails; router not included (65 mm trim router or VFD spindle)'
    ),
    (
      Brand: 'Carbide 3D';
      Model: 'Shapeoko Pro XXL';
      WorkX: 838.2; WorkY: 838.2; WorkZ: 101.6;
      BaudRate: 115200;
      SpindlePowerW: 0; SpindleMaxRPM: 0;
      ColletType: '';
      Firmware: 'GRBL 1.1';
      Notes: 'Linear rails; router not included (65 mm trim router or VFD spindle)'
    ),
    // Inventables
    (
      Brand: 'Inventables';
      Model: 'X-Carve 1000mm';
      WorkX: 750.0; WorkY: 750.0; WorkZ: 65.0;
      BaudRate: 115200;
      SpindlePowerW: 0; SpindleMaxRPM: 27000;
      ColletType: '';
      Firmware: 'GRBL (X-Controller)';
      Notes: 'DeWalt 26200 trim router, 16000-27000 RPM'
    ),
    (
      Brand: 'Inventables';
      Model: 'X-Carve Pro 4x4';
      WorkX: 1219.2; WorkY: 1219.2; WorkZ: 101.6;
      BaudRate: 115200;
      SpindlePowerW: 1500; SpindleMaxRPM: 24000;
      ColletType: 'ER16';
      Firmware: 'GRBL 1.1h (XCPd)';
      Notes: '2 HP air-cooled VFD spindle, 8000-24000 RPM'
    ),
    (
      Brand: 'Inventables';
      Model: 'X-Carve Pro 4x2';
      WorkX: 1219.2; WorkY: 609.6; WorkZ: 101.6;
      BaudRate: 115200;
      SpindlePowerW: 1500; SpindleMaxRPM: 24000;
      ColletType: 'ER16';
      Firmware: 'GRBL 1.1h (XCPd)';
      Notes: '2 HP air-cooled VFD spindle, 8000-24000 RPM'
    ),
    // FoxAlien
    (
      Brand: 'FoxAlien';
      Model: 'Masuter Pro';
      WorkX: 400.0; WorkY: 400.0; WorkZ: 60.0;
      BaudRate: 115200;
      SpindlePowerW: 0; SpindleMaxRPM: 10000;
      ColletType: '';
      Firmware: 'GRBL';
      Notes: '775 spindle; 52 mm and 65 mm clamps for spindle or laser upgrades'
    ),
    (
      Brand: 'FoxAlien';
      Model: '4040-XE';
      WorkX: 400.0; WorkY: 400.0; WorkZ: 65.0;
      BaudRate: 115200;
      SpindlePowerW: 300; SpindleMaxRPM: 0;
      ColletType: '';
      Firmware: 'GRBL';
      Notes: '300 W spindle; manufacturer does not publish its RPM'
    ),
    (
      Brand: 'FoxAlien';
      Model: 'Vasto';
      WorkX: 400.0; WorkY: 400.0; WorkZ: 100.0;
      BaudRate: 115200;
      SpindlePowerW: 400; SpindleMaxRPM: 0;
      ColletType: '';
      Firmware: 'GRBL';
      Notes: '400 W spindle; manufacturer does not publish its RPM'
    ),
    // OpenBuilds
    (
      Brand: 'OpenBuilds';
      Model: 'LEAD CNC 1010';
      WorkX: 730.0; WorkY: 810.0; WorkZ: 100.0;
      BaudRate: 115200;
      SpindlePowerW: 0; SpindleMaxRPM: 0;
      ColletType: '';
      Firmware: 'GRBL (OpenBuilds Control)';
      Notes: 'Z travel approximate; spindle/router chosen by the builder'
    ),
    (
      Brand: 'OpenBuilds';
      Model: 'MiniMill';
      WorkX: 120.0; WorkY: 180.0; WorkZ: 80.0;
      BaudRate: 115200;
      SpindlePowerW: 0; SpindleMaxRPM: 0;
      ColletType: '';
      Firmware: 'GRBL (OpenBuilds Control)';
      Notes: 'About 60 mm workable material height with spoilboard'
    ),
    // TwoTrees
    (
      Brand: 'TwoTrees';
      Model: 'TTC450';
      WorkX: 450.0; WorkY: 450.0; WorkZ: 80.0;
      BaudRate: 115200;
      SpindlePowerW: 80; SpindleMaxRPM: 8000;
      ColletType: 'ER11';
      Firmware: 'GRBL (MKS DLC32)';
      Notes: '80 W 775 spindle; optional 500 W spindle reaches 12000 RPM'
    )
  );

procedure GetRouterBrands(AList: TStrings);
var
  I: Integer;
  B: string;
begin
  AList.Clear;
  for I := 0 to ROUTER_PROFILE_COUNT - 1 do
  begin
    B := PROFILES[I].Brand;
    if AList.IndexOf(B) < 0 then
      AList.Add(B);
  end;
end;

procedure GetRouterModels(const ABrand: string; AList: TStrings);
var
  I: Integer;
begin
  AList.Clear;
  for I := 0 to ROUTER_PROFILE_COUNT - 1 do
  begin
    if SameText(PROFILES[I].Brand, ABrand) then
      AList.Add(PROFILES[I].Model);
  end;
end;

function FindRouterProfile(const ABrand, AModel: string; out AProfile: TRouterProfile): Boolean;
var
  I: Integer;
begin
  for I := 0 to ROUTER_PROFILE_COUNT - 1 do
  begin
    if SameText(PROFILES[I].Brand, ABrand) and SameText(PROFILES[I].Model, AModel) then
    begin
      AProfile := PROFILES[I];
      Exit(True);
    end;
  end;
  FillChar(AProfile, SizeOf(AProfile), 0);
  Result := False;
end;

function SpindleText(const P: TRouterProfile): string;
begin
  if P.SpindlePowerW > 0 then Result := IntToStr(P.SpindlePowerW) + ' W'
  else Result := 'power not informed';
  if P.SpindleMaxRPM > 0 then Result := Result + ', ' + IntToStr(P.SpindleMaxRPM) + ' RPM'
  else Result := Result + ', RPM not informed';
  if P.ColletType <> '' then Result := Result + ', ' + P.ColletType;
end;

function RouterProfileSummary(const P: TRouterProfile): string;
begin
  Result := Format('%s %s | Table: %.1f x %.1f x %.1f mm | Baud: %d | Spindle: %s | %s',
    [P.Brand, P.Model, P.WorkX, P.WorkY, P.WorkZ, P.BaudRate, SpindleText(P), P.Firmware],
    DefaultFormatSettings);
end;

end.
