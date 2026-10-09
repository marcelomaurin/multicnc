unit multicnc_realtime;

{$mode objfpc}{$H+}

{ Comandos em tempo real (enviados fora do fluxo de linhas, sem fim de linha)
  e calculo de sequencias de override.

  Codigos do Grbl 1.1 e extensoes do grblHAL (CMD_STATUS_REPORT_ALL 0x87,
  parada opcional, bloco unico, MPG, auto-report, soft E-stop). O FluidNC
  aceita o conjunto do Grbl 1.1. }

interface

uses SysUtils, multicnc_grbl_status;

type
  TRealtimeCommand = (
    rtStatusQuery, rtCycleStart, rtFeedHold, rtSoftReset, rtSafetyDoor,
    rtJogCancel, rtFeedReset, rtFeedPlus10, rtFeedMinus10, rtFeedPlus1,
    rtFeedMinus1, rtRapid100, rtRapid50, rtRapid25, rtSpindleReset,
    rtSpindlePlus10, rtSpindleMinus10, rtSpindlePlus1, rtSpindleMinus1,
    rtSpindleStopToggle, rtFloodToggle, rtMistToggle,
    // grblHAL
    rtStatusReportAll, rtOptionalStopToggle, rtSingleBlockToggle,
    rtAutoReportToggle, rtSoftEStop);

const
  GRBL_MIN_OVERRIDE = 10;
  GRBL_MAX_OVERRIDE = 200;

function RealtimeSupported(Cmd: TRealtimeCommand; Firmware: TGrblFirmware): Boolean;
function RealtimeByte(Cmd: TRealtimeCommand): Char;
function RealtimeName(Cmd: TRealtimeCommand): string;

{ Sequencia minima de bytes de override (passos de 10% e 1%) para levar o
  valor atual ao alvo. Alvo 100 usa o comando de reset (1 byte). }
function BuildFeedOverride(Current, Target: Integer): string;
function BuildSpindleOverride(Current, Target: Integer): string;
function BuildRapidOverride(Target: Integer): string;

implementation

function RealtimeByte(Cmd: TRealtimeCommand): Char;
begin
  case Cmd of
    rtStatusQuery: Result := '?';
    rtCycleStart: Result := '~';
    rtFeedHold: Result := '!';
    rtSoftReset: Result := #$18;
    rtSafetyDoor: Result := #$84;
    rtJogCancel: Result := #$85;
    rtFeedReset: Result := #$90;
    rtFeedPlus10: Result := #$91;
    rtFeedMinus10: Result := #$92;
    rtFeedPlus1: Result := #$93;
    rtFeedMinus1: Result := #$94;
    rtRapid100: Result := #$95;
    rtRapid50: Result := #$96;
    rtRapid25: Result := #$97;
    rtSpindleReset: Result := #$99;
    rtSpindlePlus10: Result := #$9A;
    rtSpindleMinus10: Result := #$9B;
    rtSpindlePlus1: Result := #$9C;
    rtSpindleMinus1: Result := #$9D;
    rtSpindleStopToggle: Result := #$9E;
    rtFloodToggle: Result := #$A0;
    rtMistToggle: Result := #$A1;
    rtStatusReportAll: Result := #$87;
    rtOptionalStopToggle: Result := #$88;
    rtSingleBlockToggle: Result := #$89;
    rtAutoReportToggle: Result := #$8C;
    rtSoftEStop: Result := #$9F;
  else
    Result := #0;
  end;
end;

function RealtimeSupported(Cmd: TRealtimeCommand; Firmware: TGrblFirmware): Boolean;
begin
  if Cmd in [rtStatusReportAll, rtOptionalStopToggle, rtSingleBlockToggle,
    rtAutoReportToggle, rtSoftEStop] then
    Result := Firmware = gfGrblHAL
  else
    Result := True;
end;

function RealtimeName(Cmd: TRealtimeCommand): string;
begin
  WriteStr(Result, Cmd);
end;

function StepSequence(Current, Target: Integer; Reset, Plus10, Minus10,
  Plus1, Minus1: TRealtimeCommand): string;
var Diff: Integer;
begin
  Result := '';
  if Target < GRBL_MIN_OVERRIDE then Target := GRBL_MIN_OVERRIDE;
  if Target > GRBL_MAX_OVERRIDE then Target := GRBL_MAX_OVERRIDE;
  // Comecar de 100% via reset e mais curto quando o alvo esta mais perto de 100.
  if (Target = 100) or (Abs(Target - 100) + 1 < Abs(Target - Current)) then begin
    Result := RealtimeByte(Reset);
    Current := 100;
  end;
  Diff := Target - Current;
  while Diff >= 10 do begin Result := Result + RealtimeByte(Plus10); Dec(Diff, 10); end;
  while Diff <= -10 do begin Result := Result + RealtimeByte(Minus10); Inc(Diff, 10); end;
  while Diff > 0 do begin Result := Result + RealtimeByte(Plus1); Dec(Diff); end;
  while Diff < 0 do begin Result := Result + RealtimeByte(Minus1); Inc(Diff); end;
end;

function BuildFeedOverride(Current, Target: Integer): string;
begin
  Result := StepSequence(Current, Target, rtFeedReset, rtFeedPlus10,
    rtFeedMinus10, rtFeedPlus1, rtFeedMinus1);
end;

function BuildSpindleOverride(Current, Target: Integer): string;
begin
  Result := StepSequence(Current, Target, rtSpindleReset, rtSpindlePlus10,
    rtSpindleMinus10, rtSpindlePlus1, rtSpindleMinus1);
end;

function BuildRapidOverride(Target: Integer): string;
begin
  if Target >= 100 then Result := RealtimeByte(rtRapid100)
  else if Target >= 50 then Result := RealtimeByte(rtRapid50)
  else Result := RealtimeByte(rtRapid25);
end;

end.
