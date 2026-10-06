unit multicnc_router_profiles;

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
  ROUTER_PROFILE_COUNT = 18;

procedure GetRouterBrands(AList: TStrings);
procedure GetRouterModels(const ABrand: string; AList: TStrings);
function FindRouterProfile(const ABrand, AModel: string; out AProfile: TRouterProfile): Boolean;
function RouterProfileSummary(const P: TRouterProfile): string;

implementation

const
  PROFILES: array[0..ROUTER_PROFILE_COUNT - 1] of TRouterProfile = (
    // SainSmart / Genmitsu
    (
      Brand: 'SainSmart / Genmitsu';
      Model: '3018-PRO';
      WorkX: 300.0; WorkY: 180.0; WorkZ: 45.0;
      BaudRate: 115200;
      SpindlePowerW: 120; SpindleMaxRPM: 10000;
      ColletType: 'ER11 (3.175mm)';
      Firmware: 'GRBL 1.1f';
      Notes: 'Classic desktop entry-level CNC router, aluminum table, 775 spindle motor'
    ),
    (
      Brand: 'SainSmart / Genmitsu';
      Model: '3018-PROVer V2';
      WorkX: 300.0; WorkY: 180.0; WorkZ: 40.0;
      BaudRate: 115200;
      SpindlePowerW: 120; SpindleMaxRPM: 10000;
      ColletType: 'ER11 (3.175mm)';
      Firmware: 'GRBL 1.1f';
      Notes: 'Enclosed aluminum body, emergency stop button, XYZ limit switches, Z-probe'
    ),
    (
      Brand: 'SainSmart / Genmitsu';
      Model: '3020-PRO MAX';
      WorkX: 300.0; WorkY: 200.0; WorkZ: 72.0;
      BaudRate: 115200;
      SpindlePowerW: 300; SpindleMaxRPM: 12000;
      ColletType: 'ER11 (3.175mm / 6.35mm)';
      Firmware: 'GRBL 1.1f';
      Notes: 'Heavy-duty steel dual linear rails, 300W quiet spindle, upgraded 72mm Z clearance'
    ),
    (
      Brand: 'SainSmart / Genmitsu';
      Model: 'PROVerXL 4030';
      WorkX: 400.0; WorkY: 300.0; WorkZ: 110.0;
      BaudRate: 115200;
      SpindlePowerW: 300; SpindleMaxRPM: 12000;
      ColletType: 'ER11 / 65mm clamp';
      Firmware: 'GRBL 1.1h';
      Notes: 'Rigid C-beam extrusion architecture, high Z travel, compatible with trim routers'
    ),
    (
      Brand: 'SainSmart / Genmitsu';
      Model: '4040-PRO';
      WorkX: 400.0; WorkY: 400.0; WorkZ: 78.0;
      BaudRate: 115200;
      SpindlePowerW: 710; SpindleMaxRPM: 30000;
      ColletType: '65mm Router Clamp / ER11';
      Firmware: 'GRBL 1.1h';
      Notes: 'Dual Y-axis lead screws, all-metal frame, large 400x400 mm square work area'
    ),

    // Carbide 3D
    (
      Brand: 'Carbide 3D';
      Model: 'Shapeoko 4 Standard';
      WorkX: 444.0; WorkY: 444.0; WorkZ: 101.0;
      BaudRate: 115200;
      SpindlePowerW: 750; SpindleMaxRPM: 30000;
      ColletType: '1/4 in and 1/8 in (65mm)';
      Firmware: 'GRBL 1.1';
      Notes: 'Precision lead screw Z axis, heavy aluminum extrusions, inductive proximity switches'
    ),
    (
      Brand: 'Carbide 3D';
      Model: 'Shapeoko 4 XL';
      WorkX: 838.0; WorkY: 444.0; WorkZ: 101.0;
      BaudRate: 115200;
      SpindlePowerW: 750; SpindleMaxRPM: 30000;
      ColletType: '1/4 in and 1/8 in (65mm)';
      Firmware: 'GRBL 1.1';
      Notes: 'Wide cutting envelope (33 in x 17.5 in), ideal for guitar bodies and signs'
    ),
    (
      Brand: 'Carbide 3D';
      Model: 'Shapeoko 4 XXL';
      WorkX: 838.0; WorkY: 838.0; WorkZ: 101.0;
      BaudRate: 115200;
      SpindlePowerW: 750; SpindleMaxRPM: 30000;
      ColletType: '1/4 in and 1/8 in (65mm)';
      Firmware: 'GRBL 1.1';
      Notes: 'Full-size 33 in x 33 in cutting envelope, Sweeper dust boot compatible'
    ),
    (
      Brand: 'Carbide 3D';
      Model: 'Shapeoko Pro Standard';
      WorkX: 444.0; WorkY: 444.0; WorkZ: 101.0;
      BaudRate: 115200;
      SpindlePowerW: 800; SpindleMaxRPM: 30000;
      ColletType: '1/4 in and 1/8 in (65mm / VFD)';
      Firmware: 'GRBL 1.1';
      Notes: '15mm linear rails on all axes, hybrid T-slot clamping bed with MDF wasteboard'
    ),
    (
      Brand: 'Carbide 3D';
      Model: 'Shapeoko Pro XXL';
      WorkX: 838.0; WorkY: 838.0; WorkZ: 101.0;
      BaudRate: 115200;
      SpindlePowerW: 800; SpindleMaxRPM: 30000;
      ColletType: '1/4 in and 1/8 in (65mm / VFD)';
      Firmware: 'GRBL 1.1';
      Notes: 'Large format industrial linear rails, maximum rigidity for non-ferrous metals and hardwood'
    ),

    // Inventables
    (
      Brand: 'Inventables';
      Model: 'X-Carve 1000mm';
      WorkX: 750.0; WorkY: 750.0; WorkZ: 65.0;
      BaudRate: 115200;
      SpindlePowerW: 600; SpindleMaxRPM: 27000;
      ColletType: '1/4 in (DeWalt DWP611)';
      Firmware: 'GRBL 1.1';
      Notes: 'X-Controller motion board, makerspace classic open CNC router platform'
    ),
    (
      Brand: 'Inventables';
      Model: 'X-Carve 500mm';
      WorkX: 300.0; WorkY: 300.0; WorkZ: 65.0;
      BaudRate: 115200;
      SpindlePowerW: 600; SpindleMaxRPM: 27000;
      ColletType: '1/4 in (DeWalt DWP611)';
      Firmware: 'GRBL 1.1';
      Notes: 'Compact footprint benchtop router for small precision projects and prototyping'
    ),
    (
      Brand: 'Inventables';
      Model: 'X-Carve Pro 4x4';
      WorkX: 1220.0; WorkY: 1220.0; WorkZ: 100.0;
      BaudRate: 115200;
      SpindlePowerW: 2200; SpindleMaxRPM: 24000;
      ColletType: 'ER20';
      Firmware: 'GRBL';
      Notes: 'Commercial 4x4 ft production CNC router, 3HP air-cooled spindle, ball screws on all axes'
    ),

    // FoxAlien
    (
      Brand: 'FoxAlien';
      Model: 'Masuter Pro';
      WorkX: 400.0; WorkY: 400.0; WorkZ: 60.0;
      BaudRate: 115200;
      SpindlePowerW: 300; SpindleMaxRPM: 10000;
      ColletType: 'ER11 / 65mm clamp';
      Firmware: 'GRBL 1.1';
      Notes: 'Z-axis linear rail structure, 400x400 mm aluminum T-slot table, optional 65mm router'
    ),
    (
      Brand: 'FoxAlien';
      Model: '4040-XE';
      WorkX: 400.0; WorkY: 400.0; WorkZ: 55.0;
      BaudRate: 115200;
      SpindlePowerW: 300; SpindleMaxRPM: 10000;
      ColletType: 'ER11 (3.175mm)';
      Firmware: 'GRBL 1.1';
      Notes: 'Dual Y-axis high-torque NEMA 23 stepper motors, integrated controller box'
    ),
    (
      Brand: 'FoxAlien';
      Model: 'Vasto';
      WorkX: 400.0; WorkY: 400.0; WorkZ: 95.0;
      BaudRate: 115200;
      SpindlePowerW: 400; SpindleMaxRPM: 12000;
      ColletType: 'ER11 / 65mm clamp';
      Firmware: 'GRBL 1.1';
      Notes: 'Heavy ball screws and HG-15 linear guide rails on all XYZ axes for heavy cutting'
    ),

    // OpenBuilds
    (
      Brand: 'OpenBuilds';
      Model: 'LEAD CNC 1010';
      WorkX: 730.0; WorkY: 810.0; WorkZ: 90.0;
      BaudRate: 115200;
      SpindlePowerW: 600; SpindleMaxRPM: 27000;
      ColletType: 'ER11 / RoutER11';
      Firmware: 'GRBL 1.1 (BlackBox)';
      Notes: 'Lead screw driven on all axes, BlackBox 32-bit motion controller, C-beam gantry'
    ),
    (
      Brand: 'OpenBuilds';
      Model: 'MiniMill';
      WorkX: 120.0; WorkY: 180.0; WorkZ: 80.0;
      BaudRate: 115200;
      SpindlePowerW: 300; SpindleMaxRPM: 12000;
      ColletType: 'ER11 (3.175mm)';
      Firmware: 'GRBL 1.1 (BlackBox)';
      Notes: 'Compact, rigid small-part CNC milling machine for precision aluminum and brass'
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

function RouterProfileSummary(const P: TRouterProfile): string;
begin
  Result := Format('%s %s | Table: %.0f x %.0f x %.0f mm | Baud: %d | Spindle: %dW (%d RPM) | %s',
    [P.Brand, P.Model, P.WorkX, P.WorkY, P.WorkZ, P.BaudRate,
     P.SpindlePowerW, P.SpindleMaxRPM, P.Firmware]);
end;

end.
