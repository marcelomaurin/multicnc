unit multicnc_types;

{$mode objfpc}{$H+}

interface

type
  TMachineType = (mtRouter, mtLaser, mtPrinter3D);
  TMachineState = (msDisconnected, msConnecting, msIdle, msRunning,
    msPaused, msAlarm, msError);
  TAxis = (axX, axY, axZ, axA, axE);
  TAxisSet = set of TAxis;
  { Estrategia de envio de programas (ver multicnc_streamer). }
  TStreamMode = (smCharacterCounting, smSendResponse, smMarlinChecksum);

  TMachinePosition = record
    X, Y, Z, A, E: Double;
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
function DefaultCapabilities(AType: TMachineType): TMachineCapabilities;
function MachineTypeToString(AType: TMachineType): string;
function MachineStateToString(AState: TMachineState): string;

implementation

function EmptyPosition: TMachinePosition;
begin
  FillChar(Result, SizeOf(Result), 0);
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
