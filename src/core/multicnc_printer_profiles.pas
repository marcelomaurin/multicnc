unit multicnc_printer_profiles;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TPrinterProfile = record
    Brand: string;
    Model: string;
    VolumeX: Double;
    VolumeY: Double;
    VolumeZ: Double;
    BaudRate: Integer;
    MaxHotendTemp: Integer;
    MaxBedTemp: Integer;
    HasHeatedBed: Boolean;
    FilamentDiameter: Double;
    Firmware: string;
    Notes: string;
  end;

const
  PRINTER_PROFILE_COUNT = 15;

procedure GetPrinterBrands(AList: TStrings);
procedure GetPrinterModels(const ABrand: string; AList: TStrings);
function FindPrinterProfile(const ABrand, AModel: string; out AProfile: TPrinterProfile): Boolean;
function PrinterProfileSummary(const P: TPrinterProfile): string;

const
  DEFAULT_MAX_HOTEND_TEMP = 260;
  ABSOLUTE_MAX_HOTEND_TEMP = 300;
  DEFAULT_MAX_BED_TEMP = 100;
  ABSOLUTE_MAX_BED_TEMP = 135;

function ValidateHotendTemperature(ATemp: Double; AMaxAllowed: Integer; out Reason: string): Boolean;
function ValidateBedTemperature(ATemp: Double; AMaxAllowed: Integer; out Reason: string): Boolean;

implementation

const
  PROFILES: array[0..PRINTER_PROFILE_COUNT - 1] of TPrinterProfile = (
    // Creality
    (
      Brand: 'Creality';
      Model: 'Ender-3 V2';
      VolumeX: 220.0; VolumeY: 220.0; VolumeZ: 250.0;
      BaudRate: 115200;
      MaxHotendTemp: 260; MaxBedTemp: 100;
      HasHeatedBed: True; FilamentDiameter: 1.75;
      Firmware: 'Marlin';
      Notes: 'Carborundum glass heated bed, 32-bit silent motherboard'
    ),
    (
      Brand: 'Creality';
      Model: 'Ender-3 S1';
      VolumeX: 220.0; VolumeY: 220.0; VolumeZ: 270.0;
      BaudRate: 115200;
      MaxHotendTemp: 260; MaxBedTemp: 100;
      HasHeatedBed: True; FilamentDiameter: 1.75;
      Firmware: 'Marlin';
      Notes: 'Sprite dual-gear direct extruder, CR Touch auto-leveling'
    ),
    (
      Brand: 'Creality';
      Model: 'Ender-3 V3 SE';
      VolumeX: 220.0; VolumeY: 220.0; VolumeZ: 250.0;
      BaudRate: 115200;
      MaxHotendTemp: 260; MaxBedTemp: 100;
      HasHeatedBed: True; FilamentDiameter: 1.75;
      Firmware: 'Marlin';
      Notes: 'Direct extruder, strain gauge auto Z-offset, 250 mm/s max'
    ),
    (
      Brand: 'Creality';
      Model: 'CR-10';
      VolumeX: 300.0; VolumeY: 300.0; VolumeZ: 400.0;
      BaudRate: 115200;
      MaxHotendTemp: 260; MaxBedTemp: 100;
      HasHeatedBed: True; FilamentDiameter: 1.75;
      Firmware: 'Marlin';
      Notes: 'Large format Cartesian 3D printer'
    ),
    (
      Brand: 'Creality';
      Model: 'Ender-5 Pro';
      VolumeX: 220.0; VolumeY: 220.0; VolumeZ: 300.0;
      BaudRate: 115200;
      MaxHotendTemp: 260; MaxBedTemp: 135;
      HasHeatedBed: True; FilamentDiameter: 1.75;
      Firmware: 'Marlin';
      Notes: 'Box-frame cubic architecture, Capricorn Bowden PTFE tube'
    ),

    // Prusa Research
    (
      Brand: 'Prusa Research';
      Model: 'Original Prusa i3 MK3S+';
      VolumeX: 250.0; VolumeY: 210.0; VolumeZ: 210.0;
      BaudRate: 115200;
      MaxHotendTemp: 300; MaxBedTemp: 120;
      HasHeatedBed: True; FilamentDiameter: 1.75;
      Firmware: 'Marlin';
      Notes: 'Magnetic heatbed with spring steel sheet, SuperPINDA sensor'
    ),
    (
      Brand: 'Prusa Research';
      Model: 'Original Prusa MK4';
      VolumeX: 250.0; VolumeY: 210.0; VolumeZ: 220.0;
      BaudRate: 115200;
      MaxHotendTemp: 300; MaxBedTemp: 120;
      HasHeatedBed: True; FilamentDiameter: 1.75;
      Firmware: 'Marlin';
      Notes: 'Nextruder with load cell sensor, 32-bit xBuddy board'
    ),
    (
      Brand: 'Prusa Research';
      Model: 'Original Prusa Mini+';
      VolumeX: 180.0; VolumeY: 180.0; VolumeZ: 180.0;
      BaudRate: 115200;
      MaxHotendTemp: 280; MaxBedTemp: 100;
      HasHeatedBed: True; FilamentDiameter: 1.75;
      Firmware: 'Marlin';
      Notes: 'Compact cantilever design, 32-bit Buddy motherboard'
    ),

    // Anycubic
    (
      Brand: 'Anycubic';
      Model: 'Mega S (i3 Mega)';
      VolumeX: 210.0; VolumeY: 210.0; VolumeZ: 205.0;
      BaudRate: 250000;
      MaxHotendTemp: 260; MaxBedTemp: 110;
      HasHeatedBed: True; FilamentDiameter: 1.75;
      Firmware: 'Marlin';
      Notes: 'Rigid metal frame, Ultrabase heated bed platform'
    ),
    (
      Brand: 'Anycubic';
      Model: 'Kobra Neo';
      VolumeX: 220.0; VolumeY: 220.0; VolumeZ: 250.0;
      BaudRate: 115200;
      MaxHotendTemp: 260; MaxBedTemp: 110;
      HasHeatedBed: True; FilamentDiameter: 1.75;
      Firmware: 'Marlin';
      Notes: 'Direct drive extruder, LeviQ 25-point auto bed leveling'
    ),
    (
      Brand: 'Anycubic';
      Model: 'Chiron';
      VolumeX: 400.0; VolumeY: 400.0; VolumeZ: 450.0;
      BaudRate: 250000;
      MaxHotendTemp: 260; MaxBedTemp: 100;
      HasHeatedBed: True; FilamentDiameter: 1.75;
      Firmware: 'Marlin';
      Notes: 'Extra-large build volume, dual Z-axis leadscrews'
    ),

    // Elegoo
    (
      Brand: 'Elegoo';
      Model: 'Neptune 3 Pro';
      VolumeX: 225.0; VolumeY: 225.0; VolumeZ: 280.0;
      BaudRate: 115200;
      MaxHotendTemp: 260; MaxBedTemp: 100;
      HasHeatedBed: True; FilamentDiameter: 1.75;
      Firmware: 'Marlin';
      Notes: 'Dual-gear direct extruder, 36-point auto bed leveling, PEI sheet'
    ),
    (
      Brand: 'Elegoo';
      Model: 'Neptune 3 Plus';
      VolumeX: 320.0; VolumeY: 320.0; VolumeZ: 400.0;
      BaudRate: 115200;
      MaxHotendTemp: 260; MaxBedTemp: 100;
      HasHeatedBed: True; FilamentDiameter: 1.75;
      Firmware: 'Marlin';
      Notes: 'Medium-large format, 49-point auto bed leveling'
    ),
    (
      Brand: 'Elegoo';
      Model: 'Neptune 2S';
      VolumeX: 220.0; VolumeY: 220.0; VolumeZ: 250.0;
      BaudRate: 115200;
      MaxHotendTemp: 260; MaxBedTemp: 100;
      HasHeatedBed: True; FilamentDiameter: 1.75;
      Firmware: 'Marlin';
      Notes: 'Dual-gear metal extruder, PEI magnetic platform'
    ),

    // Artillery
    (
      Brand: 'Artillery';
      Model: 'Sidewinder X2';
      VolumeX: 300.0; VolumeY: 300.0; VolumeZ: 400.0;
      BaudRate: 250000;
      MaxHotendTemp: 240; MaxBedTemp: 130;
      HasHeatedBed: True; FilamentDiameter: 1.75;
      Firmware: 'Marlin';
      Notes: 'AC heated bed, direct drive Titan extruder, synchronized dual Z'
    )
  );

procedure GetPrinterBrands(AList: TStrings);
var
  I: Integer;
  B: string;
begin
  AList.Clear;
  for I := 0 to PRINTER_PROFILE_COUNT - 1 do
  begin
    B := PROFILES[I].Brand;
    if AList.IndexOf(B) < 0 then
      AList.Add(B);
  end;
end;

procedure GetPrinterModels(const ABrand: string; AList: TStrings);
var
  I: Integer;
begin
  AList.Clear;
  for I := 0 to PRINTER_PROFILE_COUNT - 1 do
  begin
    if SameText(PROFILES[I].Brand, ABrand) then
      AList.Add(PROFILES[I].Model);
  end;
end;

function FindPrinterProfile(const ABrand, AModel: string; out AProfile: TPrinterProfile): Boolean;
var
  I: Integer;
begin
  for I := 0 to PRINTER_PROFILE_COUNT - 1 do
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

function PrinterProfileSummary(const P: TPrinterProfile): string;
begin
  Result := Format('%s %s | Volume: %.0f x %.0f x %.0f mm | Baud: %d | Hotend: %d C | Bed: %d C (%s)',
    [P.Brand, P.Model, P.VolumeX, P.VolumeY, P.VolumeZ, P.BaudRate,
     P.MaxHotendTemp, P.MaxBedTemp, P.Firmware]);
end;

function ValidateHotendTemperature(ATemp: Double; AMaxAllowed: Integer; out Reason: string): Boolean;
var
  Ceiling: Integer;
begin
  Reason := '';
  if (AMaxAllowed <= 0) or (AMaxAllowed > ABSOLUTE_MAX_HOTEND_TEMP) then
    Ceiling := ABSOLUTE_MAX_HOTEND_TEMP
  else
    Ceiling := AMaxAllowed;

  if ATemp < 0 then
  begin
    Reason := 'Temperatura negativa do bico é inválida.';
    Exit(False);
  end;

  if ATemp > Ceiling then
  begin
    Reason := Format('Temperatura do bico (%.0f °C) excede o limite seguro permitido (%d °C). Bloqueado para evitar queima da máquina.',
      [ATemp, Ceiling]);
    Exit(False);
  end;

  Result := True;
end;

function ValidateBedTemperature(ATemp: Double; AMaxAllowed: Integer; out Reason: string): Boolean;
var
  Ceiling: Integer;
begin
  Reason := '';
  if (AMaxAllowed <= 0) or (AMaxAllowed > ABSOLUTE_MAX_BED_TEMP) then
    Ceiling := ABSOLUTE_MAX_BED_TEMP
  else
    Ceiling := AMaxAllowed;

  if ATemp < 0 then
  begin
    Reason := 'Temperatura negativa da cama é inválida.';
    Exit(False);
  end;

  if ATemp > Ceiling then
  begin
    Reason := Format('Temperatura da cama (%.0f °C) excede o limite seguro permitido (%d °C). Bloqueado para evitar queima da máquina.',
      [ATemp, Ceiling]);
    Exit(False);
  end;

  Result := True;
end;

end.
