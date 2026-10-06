unit multicnc_laser_config;

{ objfpc}{+}

interface

uses
  Classes, SysUtils, Math, multisuite_numfmt;

type
  TLaserWorkMode = (lwmEngrave, lwmCut, lwmPerforate);
  TLaserControlMode = (lcmM4Dynamic, lcmM3Constant);

  TLaserSettings = record
    WorkMode: TLaserWorkMode;
    LaserPower: Double;         // 0..100 %
    MinPower: Double;           // 0..100 %
    MaxPower: Double;           // 0..100 %
    MaxS: Integer;              // default 1000 ()
    EngraveFeed: Double;        // mm/min
    CutFeed: Double;            // mm/min
    RapidFeed: Double;          // mm/min
    OverrideSpeeds: Boolean;
    // Corte
    PassCount: Integer;         // 1..50
    PassPower: Double;          // 0..100 %
    PassFeed: Double;           // mm/min
    PassPauseMS: Integer;       // ms
    PassZStep: Double;          // mm
    // Picote
    PerforateOnLength: Double;  // mm (ex: 5.0)
    PerforateOffLength: Double; // mm (ex: 2.0)
    PerforatePower: Double;     // %
    PerforateFeed: Double;      // mm/min
    // Assistência de ar
    AirAssist: Boolean;         // default True
    AirAssistOnCmd: string;     // 'M8'
    AirAssistOffCmd: string;    // 'M9'
    // Controle do laser
    ControlMode: TLaserControlMode; // lcmM4Dynamic default
    // Parâmetros adicionais
    FramingLaser: Boolean;      // default False
    FramingPower: Double;       // default 1 %
    FramingFeed: Double;        // default 3000 mm/min
    PreFireMS: Integer;         // ms
    PostFireMS: Integer;        // ms
    Kerf: Double;               // default 0.10 mm
    FrameBeforeStart: Boolean;  // default False

  end;

function LaserCalcPowerS(const Settings: TLaserSettings; APercent: Double): Integer;
function LaserSummaryString(const Settings: TLaserSettings): string;

function DefaultLaserSettings: TLaserSettings;
function TransformGCodeForLaser(ASourceLines: TStrings; const Settings: TLaserSettings): TStringList;

implementation

function DefaultLaserSettings: TLaserSettings;
begin
  Result.WorkMode := lwmCut;
  Result.LaserPower := 70.0;
  Result.MinPower := 0.0;
  Result.MaxPower := 100.0;
  Result.MaxS := 1000;
  Result.EngraveFeed := 3000.0;
  Result.CutFeed := 800.0;
  Result.RapidFeed := 5000.0;
  Result.OverrideSpeeds := False;

  Result.PassCount := 1;
  Result.PassPower := 100.0;
  Result.PassFeed := 800.0;
  Result.PassPauseMS := 0;
  Result.PassZStep := 0.0;

  Result.PerforateOnLength := 5.0;
  Result.PerforateOffLength := 2.0;
  Result.PerforatePower := 70.0;
  Result.PerforateFeed := 1000.0;

  Result.AirAssist := True;
  Result.AirAssistOnCmd := 'M8';
  Result.AirAssistOffCmd := 'M9';

  Result.ControlMode := lcmM4Dynamic;

  Result.FramingLaser := False;
  Result.FramingPower := 1.0;
  Result.FramingFeed := 3000.0;
  Result.PreFireMS := 0;
  Result.PostFireMS := 0;
  Result.Kerf := 0.10;
  Result.FrameBeforeStart := False;
end;

function LaserCalcPowerS(const Settings: TLaserSettings; APercent: Double): Integer;
var P: Double;
begin
  P := EnsureRange(APercent, 0.0, 100.0);
  Result := Round((P / 100.0) * Settings.MaxS);
end;

function LaserSummaryString(const Settings: TLaserSettings): string;
var ModeName, AirStr: string; Pwr: Double; Feed: Double;
begin
  case Settings.WorkMode of
    lwmEngrave: begin ModeName := 'Engraving'; Pwr := Settings.LaserPower; Feed := Settings.EngraveFeed; end;
    lwmCut:     begin ModeName := 'Cutting'; Pwr := Settings.PassPower; Feed := Settings.PassFeed; end;
    lwmPerforate: begin ModeName := 'Perforating'; Pwr := Settings.PerforatePower; Feed := Settings.PerforateFeed; end;
  end;
  if Settings.AirAssist then AirStr := 'Yes' else AirStr := 'No';
  Result := Format('Mode: %s (%.0f%%) | %.0f mm/min | %d pass(es) | Air: %s',
    [ModeName, Pwr, Feed, Settings.PassCount, AirStr], InvariantFS);
end;

function TransformGCodeForLaser(ASourceLines: TStrings; const Settings: TLaserSettings): TStringList;
var
  Pass, I, SVal: Integer;
  Line, LaserCmd: string;
  EffectiveFeed: Double;
begin
  Result := TStringList.Create;
  if (ASourceLines = nil) or (ASourceLines.Count = 0) then Exit;

  // Determina comando do laser (M4 dinamico ou M3 constante)
  if Settings.ControlMode = lcmM4Dynamic then LaserCmd := 'M4' else LaserCmd := 'M3';
  SVal := LaserCalcPowerS(Settings, Settings.LaserPower);
  if Settings.WorkMode = lwmCut then
  begin
    SVal := LaserCalcPowerS(Settings, Settings.PassPower);
    EffectiveFeed := Settings.PassFeed;
  end
  else if Settings.WorkMode = lwmEngrave then
  begin
    EffectiveFeed := Settings.EngraveFeed;
  end
  else
  begin
    SVal := LaserCalcPowerS(Settings, Settings.PerforatePower);
    EffectiveFeed := Settings.PerforateFeed;
  end;

  Result.Add('; === MultiCNC Laser Preparation ===');
  if Settings.AirAssist and (Trim(Settings.AirAssistOnCmd) <> '') then
    Result.Add(Trim(Settings.AirAssistOnCmd) + ' ; Air assist on');

  for Pass := 1 to Max(1, Settings.PassCount) do
  begin
    if (Settings.WorkMode = lwmCut) and (Settings.PassCount > 1) then
      Result.Add(Format('; --- Pass %d of %d ---', [Pass, Settings.PassCount]));

    for I := 0 to ASourceLines.Count - 1 do
    begin
      Line := Trim(ASourceLines[I]);
      if Line = '' then Continue;

      // Substituicao de M3 / M4 conforme modo configurado
      if (Copy(Line, 1, 3) = 'M3 ') or (Line = 'M3') then
        Line := LaserCmd + Copy(Line, 3, MaxInt)
      else if (Copy(Line, 1, 3) = 'M4 ') or (Line = 'M4') then
        Line := LaserCmd + Copy(Line, 3, MaxInt);

      // Substituicao de velocidade se habilitado
      if Settings.OverrideSpeeds and ((Copy(Line, 1, 3) = 'G1 ') or (Copy(Line, 1, 3) = 'G2 ') or (Copy(Line, 1, 3) = 'G3 ')) then
      begin
        if Pos(' F', Line) > 0 then
          Line := Line + Format(' F%.0f', [EffectiveFeed], InvariantFS);
      end;

      Result.Add(Line);
    end;

    // Entre passadas no corte
    if (Settings.WorkMode = lwmCut) and (Pass < Settings.PassCount) then
    begin
      if Settings.PassZStep > 0 then
        Result.Add(Format('G91 G0 Z-%.3f G90 ; Z step per pass', [Settings.PassZStep], InvariantFS));
      if Settings.PassPauseMS > 0 then
        Result.Add(Format('G4 P%.3f ; Pause between passes', [Settings.PassPauseMS / 1000.0], InvariantFS));
    end;
  end;

  // Encerramento seguro do laser e assistencia de ar
  Result.Add('M5 ; Laser off');
  if Settings.AirAssist and (Trim(Settings.AirAssistOffCmd) <> '') then
    Result.Add(Trim(Settings.AirAssistOffCmd) + ' ; Air assist off');
  Result.Add('; === Laser Job End ===');
end;

end.
