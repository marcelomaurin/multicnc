program test_printer_temperatures;
{$mode objfpc}{$H+}
uses
  Classes, SysUtils, multisuite_numfmt, multicnc_types, multicnc_interfaces,
  multicnc_simulator, multicnc_marlin, multicnc_machine, multicnc_session,
  multicnc_printer_profiles, multicnc_safety;

procedure Check(Value: Boolean; const Msg: string);
begin
  if not Value then raise Exception.Create('TEST FAILED: ' + Msg);
end;

procedure TestTemperatureParsing;
var
  T: TPrinterTemperatures;
begin
  T := EmptyTemperatures;
  Check(ParseMarlinTemperatures('ok T:210.5 /200.0 B:60.2 /60.0 @:127 B@:0', T), 'Parse full Marlin M105');
  Check(Abs(T.HotendActual - 210.5) < 0.01, 'Hotend real matches');
  Check(Abs(T.HotendTarget - 200.0) < 0.01, 'Hotend target matches');
  Check(Abs(T.BedActual - 60.2) < 0.01, 'Bed real matches');
  Check(Abs(T.BedTarget - 60.0) < 0.01, 'Bed target matches');
  Check(T.HasReadings, 'HasReadings flag is set');

  // Test printer without heated bed
  T := EmptyTemperatures;
  Check(ParseMarlinTemperatures('ok T:24.0 /0.0', T), 'Parse nozzle only');
  Check(Abs(T.HotendActual - 24.0) < 0.01, 'Nozzle real matches');
  Check(Abs(T.HotendTarget - 0.0) < 0.01, 'Nozzle target matches');
  Check(T.BedActual = 0.0, 'Bed actual is zero');
end;

procedure TestCommandGeneration;
var
  Marlin: TMarlinProtocol;
begin
  Marlin := TMarlinProtocol.Create;
  try
    Check(Trim(Marlin.BuildQueryTemperaturesCommand) = 'M105', 'M105 command generated');
    Check(Trim(Marlin.BuildSetHotendTemperatureCommand(210)) = 'M104 S210', 'M104 command generated');
    Check(Trim(Marlin.BuildSetBedTemperatureCommand(65)) = 'M140 S65', 'M140 command generated');
  finally
    Marlin.Free;
  end;
end;

procedure TestManufacturerProfilesAndLimits;
var
  P: TPrinterProfile;
  Reason: string;
begin
  // Test Creality Ender-3 V2 profile specs
  Check(FindPrinterProfile('Creality', 'Ender-3 V2', P), 'Found Ender-3 V2 profile');
  Check(P.BaudRate = 115200, 'Ender-3 V2 baud rate is 115200');
  Check((P.VolumeX = 220) and (P.VolumeY = 220) and (P.VolumeZ = 250), 'Ender-3 V2 volume 220x220x250');
  Check(P.MaxHotendTemp = 260, 'Ender-3 V2 max hotend temp is 260');
  Check(P.MaxBedTemp = 100, 'Ender-3 V2 max bed temp is 100');

  // Test Anycubic Mega S profile specs (uses 250000 baud)
  Check(FindPrinterProfile('Anycubic', 'Mega S (i3 Mega)', P), 'Found Anycubic Mega S profile');
  Check(P.BaudRate = 250000, 'Anycubic Mega S baud rate is 250000');
  Check((P.VolumeX = 210) and (P.VolumeY = 210) and (P.VolumeZ = 205), 'Anycubic Mega S volume 210x210x205');

  // Test Prusa Research MK4 profile specs
  Check(FindPrinterProfile('Prusa Research', 'Original Prusa MK4', P), 'Found Prusa MK4 profile');
  Check(P.MaxHotendTemp = 300, 'Prusa MK4 max hotend temp is 300');
  Check(P.MaxBedTemp = 120, 'Prusa MK4 max bed temp is 120');

  // Test thermal validators
  Check(ValidateHotendTemperature(200, 260, Reason), 'Normal 200 C hotend is valid');
  Check(ValidateHotendTemperature(260, 260, Reason), 'Boundary 260 C hotend is valid');
  Check(not ValidateHotendTemperature(280, 260, Reason), 'Overheat 280 C hotend blocked for 260 C limit');
  Check(Pos('excede o limite', Reason) > 0, 'Reason explains block');
  Check(not ValidateHotendTemperature(-5, 260, Reason), 'Negative hotend temp blocked');
  Check(not ValidateHotendTemperature(450, 300, Reason), 'Extreme 450 C hotend blocked by absolute ceiling');

  Check(ValidateBedTemperature(60, 100, Reason), 'Normal 60 C bed is valid');
  Check(ValidateBedTemperature(100, 100, Reason), 'Boundary 100 C bed is valid');
  Check(not ValidateBedTemperature(110, 100, Reason), 'Overheat 110 C bed blocked for 100 C limit');
  Check(not ValidateBedTemperature(200, 135, Reason), 'Overheat 200 C bed blocked by absolute ceiling');
end;

procedure TestSafetyValidatorThermalProtection;
var
  Reason: string;
begin
  // Safe commands should pass
  Check(TSafetyValidator.CheckCommand(msIdle, 'M104 S200', Reason), 'Safe M104 S200 accepted');
  Check(TSafetyValidator.CheckCommand(msIdle, 'M140 S60', Reason), 'Safe M140 S60 accepted');
  Check(TSafetyValidator.CheckCommand(msIdle, 'M109 S215', Reason), 'Safe M109 S215 accepted');
  Check(TSafetyValidator.CheckCommand(msIdle, 'M190 S65', Reason), 'Safe M190 S65 accepted');

  // Hazardous overheating commands MUST be blocked to prevent fire/burnout
  Check(not TSafetyValidator.CheckCommand(msIdle, 'M104 S350', Reason), 'Hazardous M104 S350 blocked');
  Check(Pos('Thermal Safety', Reason) > 0, 'Reason indicates thermal safety block for hotend');

  Check(not TSafetyValidator.CheckCommand(msIdle, 'M109 S500', Reason), 'Hazardous M109 S500 blocked');
  Check(not TSafetyValidator.CheckCommand(msIdle, 'M140 S180', Reason), 'Hazardous M140 S180 blocked');
  Check(Pos('Thermal Safety', Reason) > 0, 'Reason indicates thermal safety block for bed');

  Check(not TSafetyValidator.CheckCommand(msIdle, 'M104 S-20', Reason), 'Negative M104 blocked');
end;

procedure TestSessionTemperatureIntegration;
var
  S: TSimulationSession;
  Trans: TSimulatorTransport;
  Temps: TPrinterTemperatures;
  Deadline: QWord;
begin
  S := TSimulationSession.Create;
  try
    Trans := TSimulatorTransport.Create;
    Check(S.ConnectTransport(mtPrinter3D, pkMarlin, Trans, Trans), 'Connected 3D printer session');
    Check(S.Connected, 'Session is connected');

    Deadline := GetTickCount64 + 4000;
    repeat S.Poll; Sleep(10); until S.ControllerReady or (GetTickCount64 >= Deadline);
    Check(S.ControllerReady, 'Firmware ready before querying temperatures');

    // Query temperatures
    Check(S.QueryTemperatures, 'QueryTemperatures returned true');
    S.Poll;

    Temps := S.Temperatures;
    Check(Temps.HasReadings, 'Live temperatures received from simulator');
    Check(Abs(Temps.HotendActual - 205.0) < 0.01, 'Simulator hotend actual received');
    Check(Abs(Temps.HotendTarget - 200.0) < 0.01, 'Simulator hotend target received');
    Check(Abs(Temps.BedActual - 60.0) < 0.01, 'Simulator bed actual received');
    Check(Abs(Temps.BedTarget - 60.0) < 0.01, 'Simulator bed target received');

    // Set valid temperatures
    Check(S.SetHotendTemperature(220), 'Set hotend temp 220');
    Check(S.SetBedTemperature(70), 'Set bed temp 70');

    // Set thermal limits for Creality (260 hotend, 100 bed)
    S.SetThermalLimits(260, 100);

    // Overheat attempts must be rejected by machine layer
    Check(not S.SetHotendTemperature(280), 'Machine rejected hotend above 260');
    Check(not S.SetBedTemperature(120), 'Machine rejected bed above 100');

    S.Disconnect;
    Check(not S.Connected, 'Disconnected cleanly');
  finally
    S.Free;
  end;
end;

begin
  WriteLn('Testing 3D Printer Temperature Parsing, Profiles, Safety Limits and Management...');
  TestTemperatureParsing;
  TestCommandGeneration;
  TestManufacturerProfilesAndLimits;
  TestSafetyValidatorThermalProtection;
  TestSessionTemperatureIntegration;
  WriteLn('ALL 3D PRINTER TEMPERATURE & SAFETY TESTS PASSED!');
end.
