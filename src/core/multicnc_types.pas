unit multicnc_types;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, StrUtils, multisuite_numfmt;

type
  TMachineType = (mtRouter, mtLaser, mtPrinter3D);
  TMachineState = (msDisconnected, msConnecting, msIdle, msRunning,
    msPaused, msAlarm, msError);
  TAxis = (axX, axY, axZ, axA, axE);
  TAxisSet = set of TAxis;

  TMachinePosition = record
    X, Y, Z, A, E: Double;
  end;

  TPrinterTemperatures = record
    HotendActual: Double;  { Valor real do bico lido do equipamento }
    HotendTarget: Double;  { Valor de configuracao / alvo do bico }
    BedActual: Double;     { Valor real da mesa lido do equipamento }
    BedTarget: Double;     { Valor de configuracao / alvo da mesa }
    HasReadings: Boolean;
  end;

  TMachineCapabilities = record
    Axes: TAxisSet;
    HasSpindle: Boolean;
    HasLaser: Boolean;
    HasProbe: Boolean;
    HasHotend: Boolean;
    HasHeatedBed: Boolean;
    HasExtruder: Boolean;
    HasFan: Boolean;
    HasAirAssist: Boolean;
  end;

function EmptyPosition: TMachinePosition;
function EmptyTemperatures: TPrinterTemperatures;
function ParseMarlinTemperatures(const S: string; var Temps: TPrinterTemperatures): Boolean;
function DefaultCapabilities(AType: TMachineType): TMachineCapabilities;
function MachineTypeToString(AType: TMachineType): string;
function MachineStateToString(AState: TMachineState): string;

implementation

function EmptyPosition: TMachinePosition;
begin
  FillChar(Result, SizeOf(Result), 0);
end;

function EmptyTemperatures: TPrinterTemperatures;
begin
  FillChar(Result, SizeOf(Result), 0);
end;

function ParseTempPair(const S, Key: string; out Actual, Target: Double): Boolean;
var
  I, SlashPos, EndPos: Integer;
  ActualStr, TargetStr: string;
begin
  Result := False;
  Actual := 0; Target := 0;
  I := Pos(Key, S);
  if I = 0 then Exit;
  Inc(I, Length(Key));
  while (I <= Length(S)) and (S[I] = ' ') do Inc(I);

  SlashPos := PosEx('/', S, I);
  if SlashPos = 0 then Exit;

  ActualStr := Trim(Copy(S, I, SlashPos - I));

  I := SlashPos + 1;
  while (I <= Length(S)) and (S[I] = ' ') do Inc(I);
  EndPos := I;
  while (EndPos <= Length(S)) and (S[EndPos] in ['0'..'9', '.', '-', '+']) do Inc(EndPos);

  TargetStr := Trim(Copy(S, I, EndPos - I));

  Result := TryStrToFloat(ActualStr, Actual, InvariantFS) and
            TryStrToFloat(TargetStr, Target, InvariantFS);
end;

function ParseMarlinTemperatures(const S: string; var Temps: TPrinterTemperatures): Boolean;
var Act, Tgt: Double; Found: Boolean;
begin
  Found := False;
  if ParseTempPair(S, 'T:', Act, Tgt) or ParseTempPair(S, 'T :', Act, Tgt) then
  begin
    Temps.HotendActual := Act;
    Temps.HotendTarget := Tgt;
    Temps.HasReadings := True;
    Found := True;
  end;
  if ParseTempPair(S, 'B:', Act, Tgt) or ParseTempPair(S, 'B :', Act, Tgt) then
  begin
    Temps.BedActual := Act;
    Temps.BedTarget := Tgt;
    Temps.HasReadings := True;
    Found := True;
  end;
  Result := Found;
end;

function DefaultCapabilities(AType: TMachineType): TMachineCapabilities;
begin
  FillChar(Result, SizeOf(Result), 0);
  case AType of
    mtRouter:
      begin
        Result.Axes := [axX, axY, axZ];
        Result.HasSpindle := True;
        Result.HasProbe := True;
      end;
    mtLaser:
      begin
        Result.Axes := [axX, axY];
        Result.HasLaser := True;
      end;
    mtPrinter3D:
      begin
        Result.Axes := [axX, axY, axZ, axE];
        Result.HasHotend := True;
        Result.HasHeatedBed := True;
        Result.HasExtruder := True;
        Result.HasFan := True;
      end;
  end;
end;

function MachineTypeToString(AType: TMachineType): string;
begin
  case AType of
    mtRouter: Result := 'Router';
    mtLaser: Result := 'Laser';
    mtPrinter3D: Result := 'Printer3D';
  end;
end;

function MachineStateToString(AState: TMachineState): string;
begin
  case AState of
    msDisconnected: Result := 'Disconnected';
    msConnecting: Result := 'Connecting';
    msIdle: Result := 'Idle';
    msRunning: Result := 'Running';
    msPaused: Result := 'Paused';
    msAlarm: Result := 'Alarm';
    msError: Result := 'Error';
  end;
end;

end.
